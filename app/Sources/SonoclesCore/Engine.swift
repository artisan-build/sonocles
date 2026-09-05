@preconcurrency import AVFoundation
import Foundation

/// A transcription engine.
///
/// The point of this protocol is comparison. Apple's `SpeechTranscriber` and
/// Parakeet-on-the-ANE have almost nothing in common internally — one is a
/// system service handing back attributed strings on its own schedule, the
/// other a Core ML graph we drive chunk by chunk — but the project only has two
/// questions: when does text arrive, and what audio does it describe. Both can
/// answer, so both go behind the same three calls and get measured by the same
/// instrument on the same audio.
///
/// `feed` is called from the real-time audio thread and must not block. Every
/// implementation hands off to its own queue or stream and returns.
public protocol SpeechEngine: Sendable {
    /// Shown at startup so a trace is self-identifying.
    var name: String { get }

    /// Load models, downloading if missing, and begin accepting audio.
    ///
    /// `onHypothesis` receives an arrival stamp taken as close to the source as
    /// the engine allows, so reported cadence is the engine's and not ours.
    func start(onHypothesis: @escaping @Sendable (Hypothesis, UInt64) -> Void) async throws

    /// The format this engine wants, or `nil` to take the hardware format
    /// unconverted. Engines that resample internally return `nil` rather than
    /// have us do it twice.
    func preferredFormat() async -> AVAudioFormat?

    /// Hand over one buffer of captured audio. Called on the audio thread.
    func feed(_ buffer: AVAudioPCMBuffer)

    /// Monotonic stamp helper, so engines timestamp arrivals consistently.
    static func now() -> UInt64
}

extension SpeechEngine {
    public static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
}

/// Which engine to run.
public enum EngineChoice: String, Sendable, CaseIterable {
    case fluid160
    case fluid320
    case fluid1280
    case apple

    public var label: String {
        switch self {
        case .fluid160: return "Parakeet 160 ms"
        case .fluid320: return "Parakeet 320 ms"
        case .fluid1280: return "Parakeet 1280 ms"
        case .apple: return "Apple SpeechAnalyzer"
        }
    }

    /// What the CLI accepts, and what settings persist.
    public var slug: String { rawValue }
}
