@preconcurrency import AVFoundation
import FluidAudio
import Foundation
import os

/// One capture session: microphone in, hypotheses out.
///
/// Deliberately owns no sockets. Transports outlive sessions — see `Service` —
/// because a stopped session has to be startable again over the very socket it
/// would otherwise have taken down when it stopped.
public final class Sidecar: @unchecked Sendable {
    public struct Config: Sendable {
        public var engine: EngineChoice
        public var locale: String
        public var tapFrames: AVAudioFrameCount

        public init(
            engine: EngineChoice = .fluid160,
            locale: String = Locale.current.identifier(.bcp47),
            tapFrames: AVAudioFrameCount = 4096
        ) {
            self.engine = engine
            self.locale = locale
            self.tapFrames = tapFrames
        }
    }

    private let config: Config
    private let capture: AudioCapture
    private let engine: SpeechEngine
    private let sequence = OSAllocatedUnfairLock(initialState: 0)

    /// Every hypothesis, with the frame that will go on the wire.
    public var onFrame: (@Sendable (Hypothesis, Frame, UInt64) -> Void)?

    /// Model download and compilation progress, before capture can begin.
    public var onPreparation: (@Sendable (Preparation) -> Void)? {
        get { (engine as? FluidEngine)?.onPreparation }
        set { (engine as? FluidEngine)?.onPreparation = newValue }
    }

    /// Peak input level in dBFS, straight off the audio thread.
    public var onLevel: (@Sendable (Double) -> Void)? {
        get { capture.onLevel }
        set { capture.onLevel = newValue }
    }

    public init(config: Config, note: @escaping @Sendable (String) -> Void) throws {
        self.config = config
        self.capture = AudioCapture(tapFrames: config.tapFrames)

        switch config.engine {
        case .fluid160:
            engine = FluidEngine(chunk: .ms160, note: note)
        case .fluid320:
            engine = FluidEngine(chunk: .ms320, note: note)
        case .fluid1280:
            engine = FluidEngine(chunk: .ms1280, note: note)
        case .apple:
            guard #available(macOS 26.0, *) else { throw SidecarError.appleEngineUnavailable }
            engine = AppleEngine(locale: Locale(identifier: config.locale), note: note)
        }
    }

    public var engineName: String { engine.name }
    public var hardwareFormat: AVAudioFormat? { capture.hardwareFormat }
    public var engineFormat: AVAudioFormat? { capture.engineFormat }
    public var tapFrames: AVAudioFrameCount { capture.tapFrames }

    public func start() async throws {
        // Before anything else. Starting the engine without a grant yields a
        // pipeline that looks entirely healthy and hears nothing.
        guard await AudioCapture.requestAccess() == .granted else {
            throw SidecarError.microphoneDenied
        }

        if #available(macOS 26.0, *), let apple = engine as? AppleEngine {
            try await apple.prepare()
        }

        try await engine.start { [weak self] hypothesis, nanos in
            self?.publish(hypothesis, at: nanos)
        }

        try capture.start(feeding: engine, target: await engine.preferredFormat())
    }

    public func stop() {
        capture.stop()
    }

    private func publish(_ hypothesis: Hypothesis, at nanos: UInt64) {
        let trimmed = hypothesis.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let tidied = Hypothesis(text: trimmed, isFinal: hypothesis.isFinal, audio: hypothesis.audio)

        // Signed. A negative lag means the engine reported audio ahead of what
        // we captured — a clock disagreement to surface, not a zero to invent.
        let lagMs = hypothesis.audio.map {
            Int(((capture.clock.seconds - $0.upperBound) * 1000).rounded())
        }
        let seq = sequence.withLock {
            $0 += 1; return $0
        }

        onFrame?(tidied, Frame(hypothesis: tidied, seq: seq, lagMs: lagMs), nanos)
    }
}

public enum SidecarError: Error, LocalizedError {
    case appleEngineUnavailable
    case microphoneDenied

    public var errorDescription: String? {
        switch self {
        case .appleEngineUnavailable:
            return "The Apple engine needs macOS 26 or later. Parakeet runs on macOS 14+."
        case .microphoneDenied:
            return "Microphone access denied — System Settings › Privacy & Security › Microphone"
        }
    }
}
