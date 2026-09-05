@preconcurrency import AVFoundation
import Foundation
import os

/// How much audio we have captured, on the timeline engines report against.
///
/// Counted in frames at the capture rate rather than by taking timestamps, so
/// it stays exact and stays cheap: the audio thread does one relaxed atomic add
/// per buffer and nothing else. Counted *before* any format conversion, so the
/// clock means the same thing whichever engine is running — which is the only
/// reason two engines' lag figures can be put in the same table.
/// `OSAllocatedUnfairLock` rather than `Atomic`: the latter needs macOS 15 and
/// this package floors at 14, which is where Parakeet on Core ML runs. Unfair
/// locks carry priority inheritance, so the audio thread taking one cannot be
/// preempted-and-blocked by a lower-priority reader — the failure mode that
/// makes ordinary mutexes unsafe in a render callback.
public final class AudioClock: @unchecked Sendable {
    private let frames = OSAllocatedUnfairLock(initialState: 0)
    private let rate: Double

    public init(sampleRate: Double) {
        self.rate = sampleRate > 0 ? sampleRate : 48_000
    }

    public func advance(by count: AVAudioFrameCount) {
        frames.withLock { $0 += Int(count) }
    }

    /// The live edge: audio timestamp of the most recent captured sample.
    public var seconds: Double {
        Double(frames.withLock { $0 }) / rate
    }
}
