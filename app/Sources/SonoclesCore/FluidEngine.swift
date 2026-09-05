@preconcurrency import AVFoundation
import Foundation
import FluidAudio

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
        note("loading Parakeet EOU (\(chunkMs) ms chunks) — first run downloads from HuggingFace…")
        try await manager.loadModels()
        note("models resident")

        let (stream, cont) = AsyncStream<Box>.makeStream()
        continuation = cont

        let manager = self.manager
        let note = self.note

        Task {
            var lastText = ""
            var wasEou = false

            do {
                for await box in stream {
                    try await manager.appendAudio(box.buffer)
                    try await manager.processBufferedAudio()

                    // Stamp the instant the work finished, before the reads
                    // below can fold their own scheduling into the number.
                    let received = Self.now()

                    let text = await manager.getPartialTranscript()
                    let eou = await manager.eouDetected

                    guard text != lastText || eou != wasEou else { continue }

                    // Token timings are elapsed milliseconds from the start of
                    // the session — the same clock the audio counter runs on,
                    // so lag is directly comparable across engines.
                    let stamps = await manager.getTokenTimestampsMs()
                    let audio = stamps.last.map {
                        Double(stamps.first ?? 0) / 1000 ... Double($0) / 1000
                    }

                    if !text.isEmpty {
                        onHypothesis(
                            Hypothesis(text: text, isFinal: eou && !wasEou, audio: audio),
                            received
                        )
                    }

                    lastText = text
                    wasEou = eou
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
