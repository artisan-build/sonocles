import Foundation

/// One hypothesis from a transcription engine.
///
/// `audio` is the window of session audio the text describes, in seconds from
/// the first captured sample. It is optional because not every engine reports
/// it, and an engine that cannot say *when* something was said should say so
/// rather than have a zero invented on its behalf. That distinction is not
/// pedantry: an early version of this tool rendered "no measurement" as
/// "+0 ms" and spent a session insisting it was real-time.
public struct Hypothesis: Sendable {
    public let text: String
    public let isFinal: Bool
    public let audio: ClosedRange<Double>?

    public init(text: String, isFinal: Bool, audio: ClosedRange<Double>?) {
        self.text = text
        self.isFinal = isFinal
        self.audio = audio
    }
}

/// One hypothesis on the wire, for both SSE and WebSocket.
///
/// - `audioStart` / `audioEnd`: seconds into this session's audio that the text
///   covers — when it was *said*, on the engine's own clock.
/// - `lagMs`: the live audio edge minus `audioEnd` at emit time. Signed: a
///   negative value means the engine reported audio ahead of what we captured,
///   which is a clock disagreement worth seeing rather than clamping away.
/// - `seq`: monotonic, so a consumer can spot a dropped or reordered frame.
///
/// Arrival time is a lossy proxy for spoken time — delivery clusters rather
/// than ticking evenly — so anything placing a marker accurately, or leading a
/// scroll by a fixed amount, needs `audioEnd` and not `ts`.
public struct Frame: Encodable, Sendable {
    public let type: String
    public let text: String
    public let ts: Int
    public let seq: Int
    public let audioStart: Double?
    public let audioEnd: Double?
    public let lagMs: Int?

    public init(hypothesis: Hypothesis, seq: Int, lagMs: Int?) {
        self.type = hypothesis.isFinal ? "final" : "partial"
        self.text = hypothesis.text
        self.ts = Int(Date().timeIntervalSince1970 * 1000)
        self.seq = seq
        self.audioStart = hypothesis.audio?.lowerBound
        self.audioEnd = hypothesis.audio?.upperBound
        self.lagMs = lagMs
    }

    public var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }

        return String(data: data, encoding: .utf8)
    }
}
