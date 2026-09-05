@preconcurrency import AVFoundation
import FluidAudio
import Foundation

/// Parakeet EOU 120M on the Neural Engine, via FluidAudio's Core ML port.
///
/// The default, and the reason this project exists as its own thing.
///
/// Chosen over FluidAudio's other streaming tiers for one reason: it is the
/// only manager in the library conforming to
/// `StreamingAsrTokenTimestampProvider`, so it answers both questions we have —
/// where is the reader now, and when was that word actually said. The Nemotron
/// and Unified tiers stream too, but hand back text with no timing, which would
/// leave control-token placement guessing.
///
/// Cache-aware streaming: the encoder keeps state across chunks rather than
/// re-running over a window, so a 160 ms chunk really does mean output every
/// 160 ms rather than a sliding window pretending to.
///
/// Measured against the Apple baseline on identical audio: arrivals every
/// ~206 ms against ~3747 ms, lag ~180 ms against seconds, and words arriving
/// roughly one at a time instead of nine. See Docs/ENGINES.md.
///
/// Rather than take the library's partial callback, the driver loop asks for
/// the transcript and its token timings together after each processing pass.
/// That keeps text and timestamps consistent with each other, and puts the
/// arrival stamp where the work actually finished instead of wherever a
/// callback happened to be scheduled.
///
/// ## Utterances
///
/// The loop resets the manager after every end-of-utterance, because the
/// library latches `eouDetected` until it is reset and accumulates the
/// transcript forever otherwise. Skipping the reset produces exactly two bugs,
/// both of which survived until someone just talked at it for half a minute:
/// only the first utterance is ever finalised, and `text` grows without bound —
/// a thirty-five second session still reporting `audioStart` from second three,
/// which over a full talk means an ever-growing string in every frame at five
/// frames a second.
///
/// The cost of resetting is that token timings restart at zero, so the loop
/// keeps its own offset. Timestamps stay absolute on the session timeline,
/// which is the whole reason a consumer can trust them for placing markers.
public final class FluidEngine: SpeechEngine, @unchecked Sendable {
    public let name: String

    /// `AVAudioPCMBuffer` predates `Sendable`, and the tap hands us one per
    /// callback that nothing else touches afterwards, so moving it across the
    /// stream is safe in practice even though the compiler cannot prove it.
    private struct Box: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
    }

    private let manager: StreamingEouAsrManager
    private let chunkMs: Int
    private let note: @Sendable (String) -> Void
    private var continuation: AsyncStream<Box>.Continuation?

    /// Reports model download and compilation before listening can begin.
    public var onPreparation: (@Sendable (Preparation) -> Void)?

    public init(chunk: StreamingChunkSize, note: @escaping @Sendable (String) -> Void) {
        self.manager = StreamingEouAsrManager(chunkSize: chunk)
        self.chunkMs = chunk.durationMs
        self.note = note
        self.name = "Parakeet EOU 120M (\(chunk.durationMs) ms)"
    }

    /// Nil: the library resamples to 16 kHz mono itself, and converting twice
    /// would add latency to measure and a resampler to blame.
    public func preferredFormat() async -> AVAudioFormat? { nil }

    public func start(onHypothesis: @escaping @Sendable (Hypothesis, UInt64) -> Void) async throws {
        note("loading Parakeet EOU (\(chunkMs) ms chunks)…")

        let report = onPreparation
        try await manager.loadModels(progressHandler: { progress in
            switch progress.phase {
            case .listing:
                report?(.listing)
            case .downloading(let completed, let total):
                report?(
                    .downloading(fraction: progress.fractionCompleted, file: completed, of: total))
            case .compiling(let name):
                report?(.compiling(model: name))
            }
        })

        report?(.ready)

        let (stream, cont) = AsyncStream<Box>.makeStream()
        continuation = cont

        let manager = self.manager
        let note = self.note

        Task {
            var lastText = ""

            /// Seconds of audio handed to the engine across the whole session.
            var fedSeconds = 0.0
            /// Where the current utterance's zero sits on that timeline.
            var utteranceOffset = 0.0

            do {
                for await box in stream {
                    let format = box.buffer.format
                    if format.sampleRate > 0 {
                        fedSeconds += Double(box.buffer.frameLength) / format.sampleRate
                    }

                    try await manager.appendAudio(box.buffer)
                    try await manager.processBufferedAudio()

                    // Stamp the instant the work finished, before the reads
                    // below can fold their own scheduling into the number.
                    let received = Self.now()

                    let text = await manager.getPartialTranscript()
                    let eou = await manager.eouDetected

                    guard text != lastText || eou else { continue }

                    // Token timings are milliseconds from the start of the
                    // *utterance*, so the offset puts them back on the session
                    // timeline the audio counter runs on. That is what keeps
                    // lag comparable across engines and markers placeable.
                    let stamps = await manager.getTokenTimestampsMs()
                    let audio = stamps.last.map {
                        utteranceOffset + Double(stamps.first ?? 0) / 1000...utteranceOffset
                            + Double($0) / 1000
                    }

                    if !text.isEmpty {
                        onHypothesis(
                            Hypothesis(text: text, isFinal: eou, audio: audio),
                            received
                        )
                    }

                    if eou {
                        // Re-arm. The library latches this flag until reset, so
                        // without it no later utterance is ever finalised and
                        // the transcript accumulates for the life of the
                        // process.
                        await manager.reset()
                        utteranceOffset = fedSeconds
                        lastText = ""
                    } else {
                        lastText = text
                    }
                }
            } catch {
                note("stream error: \(error)")
            }
        }
    }

    public func feed(_ buffer: AVAudioPCMBuffer) {
        continuation?.yield(Box(buffer: buffer))
    }
}
