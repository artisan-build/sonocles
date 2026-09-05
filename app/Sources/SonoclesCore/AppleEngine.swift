@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import Speech

/// Apple's on-device `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26+).
///
/// Kept as a baseline rather than deleted, because the case against it is only
/// convincing next to the alternative on the same audio — and because a claim
/// you cannot re-run is a claim you have to take on faith.
///
/// Measured behaviour: it accumulates roughly 3.8 seconds, then delivers the
/// entire volatile evolution of the phrase at once — a dozen results at ~1 ms
/// intervals — each with its range pinned to the live audio edge. So the text
/// is never stale, but you only learn where the speaker is once every 3.8 s.
/// Neither tap size (85 ms → 21 ms moved it 7 ms) nor the analyzer's priority
/// options move that window. It is not a knob Apple exposes.
///
/// Excellent for dictation, where the block is invisible. Not usable for
/// following a reader, who covers ten words in that window.
@available(macOS 26.0, *)
public final class AppleEngine: SpeechEngine, @unchecked Sendable {
    public let name = "Apple SpeechAnalyzer"

    private let locale: Locale
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private let note: @Sendable (String) -> Void

    public init(locale: Locale, note: @escaping @Sendable (String) -> Void) {
        self.locale = locale
        self.note = note
    }

    public func preferredFormat() async -> AVAudioFormat? {
        guard let transcriber else { return nil }

        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
    }

    /// Build the transcriber up front so `preferredFormat` can be asked before
    /// `start`, which is what lets the caller set its converter up once.
    public func prepare() async throws {
        // .volatileResults gives live partials; .audioTimeRange is what lets us
        // say when a word was said rather than when we heard about it.
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.transcriber = transcriber

        // Only ask for an install when the locale is actually missing. The
        // unconditional form returns a request even when it is already present,
        // which made every launch claim to be downloading a model it had.
        let installed = Set(await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) })

        if !installed.contains(locale.identifier(.bcp47)) {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [
                transcriber
            ]) {
                note("downloading speech model for \(locale.identifier(.bcp47))…")
                try await request.downloadAndInstall()
            }
        }
    }

    public func start(onHypothesis: @escaping @Sendable (Hypothesis, UInt64) -> Void) async throws {
        guard let transcriber else { return }

        // High priority and a resident model. Measured: neither moves the
        // ~3.8 s cadence. Kept only because an all-day process should not be
        // reloading its model, not because it buys latency.
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(priority: .high, modelRetention: .processLifetime)
        )
        self.analyzer = analyzer

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont

        Task { [note] in
            do {
                for try await result in transcriber.results {
                    let received = Self.now()
                    let range = result.range
                    let start = range.start.seconds
                    let end = range.end.seconds
                    let audio = (start.isFinite && end.isFinite) ? start...max(start, end) : nil

                    onHypothesis(
                        Hypothesis(
                            text: String(result.text.characters),
                            isFinal: result.isFinal,
                            audio: audio),
                        received
                    )
                }
            } catch {
                note("results error: \(error)")
            }
        }

        try await analyzer.start(inputSequence: stream)
    }

    public func feed(_ buffer: AVAudioPCMBuffer) {
        continuation?.yield(AnalyzerInput(buffer: buffer))
    }
}
