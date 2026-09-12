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

    /// What the CLI accepts, what settings persist, and what goes on the
    /// wire: `GET /engine` answers it and `POST /engine` takes it.
    public var slug: String { rawValue }

    /// Whether this engine can run on a given OS.
    ///
    /// A pure function of the version, so it can be asserted without an
    /// engine. `apple` is `SpeechAnalyzer`, which is macOS 26 and an Xcode 26
    /// toolchain; on anything older it is compiled out and would only fail at
    /// start. Parakeet runs everywhere the package does.
    public func isAvailable(on version: OperatingSystemVersion) -> Bool {
        switch self {
        case .fluid160, .fluid320, .fluid1280:
            return true
        case .apple:
            #if compiler(>=6.2)
            return version.majorVersion >= 26
            #else
            return false
            #endif
        }
    }

    public var isAvailable: Bool {
        isAvailable(on: ProcessInfo.processInfo.operatingSystemVersion)
    }

    /// The choices this machine can run, in the order the popover shows them.
    ///
    /// On the wire as `available`, so a client on macOS 15 is not offered
    /// `apple` and then refused.
    public static var available: [EngineChoice] { allCases.filter(\.isAvailable) }
}

/// Why `POST /engine` said no. Both are the client's to fix, so both are 400.
public enum EngineError: Error, LocalizedError, Equatable {
    /// Not one of the four slugs.
    case unknown(String)
    /// A real engine this machine cannot run — `apple` below macOS 26.
    case unavailable(EngineChoice)

    public var errorDescription: String? {
        switch self {
        case .unknown(let slug):
            return "unknown engine '\(slug)' — one of "
                + EngineChoice.allCases.map(\.slug).joined(separator: ", ")
        case .unavailable(let choice):
            return "engine '\(choice.slug)' is not available on this Mac"
        }
    }
}

/// The engine changed, on the stream — so no client has to poll `/status` to
/// learn that another one switched it underneath them.
///
/// Frames have `type`; this has `event`. A consumer that only handles frames
/// skips it the way it already skips the WebSocket auth answer.
public struct EngineEvent: Encodable, Sendable {
    public let event = "engine"
    public let engine: String
    public let label: String

    public init(_ choice: EngineChoice) {
        self.engine = choice.slug
        self.label = choice.label
    }

    public var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
