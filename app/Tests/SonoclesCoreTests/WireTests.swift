import Foundation
import Testing

@testable import SonoclesCore

/// The wire format is a contract with pteroprompter, so the things documented
/// in docs/PROTOCOL.md are asserted here rather than assumed.
@Suite("Wire format")
struct WireTests {
    @Test("A frame carries the documented fields")
    func fields() throws {
        let hypothesis = Hypothesis(text: "the menu bar app", isFinal: false, audio: 40.28...41.0)
        let frame = Frame(hypothesis: hypothesis, seq: 4, lagMs: 200)
        let object = try decode(frame)

        #expect(object["type"] as? String == "partial")
        #expect(object["text"] as? String == "the menu bar app")
        #expect(object["seq"] as? Int == 4)
        #expect(object["lagMs"] as? Int == 200)
        #expect(object["audioStart"] as? Double == 40.28)
        #expect(object["audioEnd"] as? Double == 41.0)
        #expect(object["ts"] != nil)
    }

    @Test("A final is typed as one")
    func finalType() throws {
        let hypothesis = Hypothesis(text: "done", isFinal: true, audio: 0...1)
        let object = try decode(Frame(hypothesis: hypothesis, seq: 1, lagMs: 0))

        #expect(object["type"] as? String == "final")
    }

    /// The documented promise is that an unmeasured lag is *absent*, never zero.
    /// An early build rendered "no measurement" as `+0ms` and spent a session
    /// insisting it was real-time while measuring nothing, so this is the single
    /// most important assertion in the file.
    @Test("An unmeasured lag is omitted, not zeroed")
    func absentLagIsAbsent() throws {
        let hypothesis = Hypothesis(text: "no timing", isFinal: false, audio: nil)
        let object = try decode(Frame(hypothesis: hypothesis, seq: 7, lagMs: nil))

        #expect(object["lagMs"] == nil)
        #expect(object["audioStart"] == nil)
        #expect(object["audioEnd"] == nil)
        #expect(object["text"] as? String == "no timing")
    }

    /// Negative lag means the engine reported audio ahead of what we captured.
    /// That is a real clock disagreement and must survive to the consumer.
    @Test("Negative lag survives encoding")
    func negativeLag() throws {
        let hypothesis = Hypothesis(text: "ahead", isFinal: false, audio: 0...5)
        let object = try decode(Frame(hypothesis: hypothesis, seq: 2, lagMs: -40))

        #expect(object["lagMs"] as? Int == -40)
    }

    private func decode(_ frame: Frame) throws -> [String: Any] {
        let json = try #require(frame.json)
        let data = try #require(json.data(using: .utf8))

        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

@Suite("Audio clock")
struct AudioClockTests {
    @Test("Seconds follow captured frames at the capture rate")
    func advances() {
        let clock = AudioClock(sampleRate: 48_000)
        #expect(clock.seconds == 0)

        clock.advance(by: 48_000)
        #expect(abs(clock.seconds - 1.0) < 0.0001)

        clock.advance(by: 24_000)
        #expect(abs(clock.seconds - 1.5) < 0.0001)
    }

    /// A zero rate would divide by zero and poison every lag figure downstream,
    /// so the clock refuses it rather than propagating a NaN.
    @Test("A nonsense sample rate falls back instead of producing NaN")
    func guardsAgainstZeroRate() {
        let clock = AudioClock(sampleRate: 0)
        clock.advance(by: 48_000)

        #expect(clock.seconds.isFinite)
        #expect(clock.seconds > 0)
    }
}
