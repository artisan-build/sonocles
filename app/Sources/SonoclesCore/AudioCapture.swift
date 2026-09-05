@preconcurrency import AVFoundation
import Foundation

/// Microphone capture, engine-agnostic.
///
/// Owns the tap, the clock and the format conversion, so an engine only has to
/// know how to turn audio into text. The split matters for measurement: capture
/// is identical for every engine, which is what makes their numbers comparable.
public final class AudioCapture: @unchecked Sendable {
    /// A one-shot latch for the converter's input callback.
    private final class OneShot: @unchecked Sendable {
        var spent = false
    }

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?

    public private(set) var clock = AudioClock(sampleRate: 48_000)
    public private(set) var hardwareFormat: AVAudioFormat?
    public private(set) var engineFormat: AVAudioFormat?

    /// Frames the tap accumulates before anything downstream sees them.
    ///
    /// Pure additive latency and the cheapest knob in the pipeline, which is
    /// why it is configurable rather than assumed: against the Apple engine,
    /// cutting it from 85 ms to 21 ms moved the delivery cadence by 7 ms, and
    /// knowing that is worth more than guessing at it.
    public let tapFrames: AVAudioFrameCount

    public init(tapFrames: AVAudioFrameCount = 4096) {
        self.tapFrames = tapFrames
    }

    /// Ask for the microphone, and wait for the answer.
    ///
    /// This has to be explicit. `AVAudioEngine` on macOS does not prompt: with
    /// no grant it starts perfectly happily and delivers silence forever, so
    /// the failure presents as a working pipeline that transcribes nothing —
    /// running engine, bound sockets, `listening: true`, and not one word.
    ///
    /// It hid for a while because a CLI inherits the grant of whatever terminal
    /// launched it. The moment the same code ran inside a signed .app with its
    /// own TCC identity, it had no permission and no way to ask for one.
    public static func requestAccess() async -> AccessResult {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .granted
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio) ? .granted : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }

    public enum AccessResult: Sendable {
        case granted
        case denied
    }

    /// Peak level of the most recent buffer, in dBFS. Set on the audio thread.
    public var onLevel: (@Sendable (Double) -> Void)?

    public func start(feeding speech: SpeechEngine, target: AVAudioFormat?) throws {
        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        hardwareFormat = hw
        engineFormat = target

        if let target, target != hw {
            converter = AVAudioConverter(from: hw, to: target)
        }

        clock = AudioClock(sampleRate: hw.sampleRate)

        input.installTap(onBus: 0, bufferSize: tapFrames, format: hw) { [weak self] buffer, _ in
            guard let self else { return }

            // Level from the raw capture, so a meter reports the microphone
            // rather than anything we did to the signal afterwards.
            self.onLevel?(Self.peakDbfs(of: buffer))

            // Advance on captured audio, before conversion, so the clock means
            // the same thing for every engine.
            self.clock.advance(by: buffer.frameLength)

            guard let converter = self.converter, let target else {
                speech.feed(buffer)
                return
            }

            let ratio = target.sampleRate / hw.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1024)
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
            else { return }

            // `convert` calls this back synchronously, but that is not
            // something the compiler can see, so the one-shot flag lives behind
            // a reference rather than being captured as a var.
            let supply = OneShot()
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                if supply.spent { status.pointee = .noDataNow; return nil }
                supply.spent = true
                status.pointee = .haveData
                return buffer
            }

            guard error == nil else { return }

            speech.feed(converted)
        }

        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Peak amplitude of a buffer in dBFS.
    ///
    /// Peak rather than RMS: this is a liveness indicator, and peak reacts on
    /// the first loud sample instead of averaging a consonant into the noise
    /// floor. Runs on the audio thread, so it touches only the sample pointer.
    private static func peakDbfs(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return -120 }

        var peak: Float = 0
        let samples = channels[0]

        for i in 0..<Int(buffer.frameLength) {
            let magnitude = abs(samples[i])
            if magnitude > peak { peak = magnitude }
        }

        return peak > 0 ? max(-120, 20 * log10(Double(peak))) : -120
    }
}
