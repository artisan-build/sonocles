import Darwin
import Foundation
import os

/// The terminal monitor.
///
/// Ported unchanged from the prompter-ears spike, because every latency claim
/// in Docs/ENGINES.md came out of this exact code and a rewrite would
/// invalidate the numbers it produced.
///
/// This exists to be judged, and the first version of it failed at that. It
/// rendered the *current* hypothesis in place, which shows you what the model
/// currently believes but hides the only thing that actually answers "is this
/// real-time": when each revision arrived, and how much text came with it.
/// Six words appearing at once and six words arriving one at a time look
/// identical on a line that overwrites itself.
///
/// So every arrival now gets its own scrolling line, carrying the gap since the
/// previous one and how many words it added. Cadence becomes something you read
/// down a column instead of something you infer from a flicker.
///
/// The rest holds from before:
///
/// - **Nothing is buffered.** Every write goes straight at the file descriptor
///   with `write(2)`. Line-buffered stdio turns a live stream into a burst
///   after silence, an artefact indistinguishable from the bug we are hunting.
/// - **Input level comes from the audio thread's own numbers**, so silence is
///   never ambiguous: meter alive and text dead means capture is fine and the
///   model is late.
///
/// Everything user-visible is serialized onto `queue`. The audio thread only
/// touches `levelCentiDb`, atomic precisely so it never blocks on us.
final class Monitor: @unchecked Sendable {
    /// Peak level of the most recent buffer, in hundredths of a dBFS.
    /// Written from the real-time audio thread, read by the render tick.
    /// `OSAllocatedUnfairLock` rather than `Atomic`, which needs macOS 15 while
    /// this package floors at 14. Unfair locks carry priority inheritance, so
    /// the audio thread taking one cannot be preempted-and-blocked by a
    /// lower-priority reader.
    private let levelCentiDb = OSAllocatedUnfairLock(initialState: -12_000)

    private let queue = DispatchQueue(label: "sonocles.monitor")
    private let interactive: Bool
    private let tracePartials: Bool
    private var timer: DispatchSourceTimer?

    /// Live state, owned by `queue`.
    private var partialText = ""
    private var partialLagMs: Int?
    private var statusOnScreen = false
    private var startedNanos: UInt64 = 0
    private var lastEventNanos: UInt64?
    private var lastPartialWords = 0

    /// Ballistics for the meter, owned by `queue`.
    ///
    /// Raw peak sampled at 30 Hz flickers too hard to read. A held peak that
    /// falls at a fixed rate is what every hardware meter does, and it is the
    /// difference between "something is happening" and a legible level.
    private var heldDb = -120.0

    /// 40 dB/sec at the 33 ms render tick.
    private static let decayPerTickDb = 40.0 * 0.033

    /// `plain` forces one-line-per-event with no ANSI, which is also what you
    /// get automatically when stderr is redirected. `quiet` drops the partial
    /// trace and reports finals only.
    init(plain: Bool, quiet: Bool) {
        interactive = !plain && isatty(STDERR_FILENO) == 1
        tracePartials = !quiet
    }

    func start() {
        startedNanos = DispatchTime.now().uptimeNanoseconds

        guard interactive else { return }

        let tick = DispatchSource.makeTimerSource(queue: queue)
        // 30 Hz: fast enough to read as continuous, cheap enough to ignore.
        tick.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(8))
        tick.setEventHandler { [weak self] in self?.drawStatus() }
        tick.resume()
        timer = tick
    }

    // MARK: - audio thread

    /// Record the level of one captured buffer.
    ///
    /// Called from the real-time audio tap: stores one integer and returns. No
    /// allocation, no locks, no `Foundation`.
    func observe(peak dbfs: Double) {
        levelCentiDb.withLock { $0 = Int(dbfs * 100) }
    }

    // MARK: - events

    /// An out-of-band message. Scrolls above the status line.
    func note(_ message: String) {
        queue.async { self.commit(message) }
    }

    /// Monotonic stamp, for callers to take at the moment an event arrives.
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// A volatile hypothesis.
    ///
    /// Scrolls a trace line showing the gap since the last arrival and the word
    /// delta, then updates the live line. The delta can be negative: the model
    /// revises, and watching it take words back is real information about how
    /// settled the text is.
    func partial(_ text: String, lagMs: Int?, audio: ClosedRange<Double>?, at nanos: UInt64) {
        queue.async {
            let words = text.split(separator: " ").count
            let delta = words - self.lastPartialWords
            self.lastPartialWords = words

            if self.tracePartials {
                self.commit(self.trace(kind: "part", delta: delta, lagMs: lagMs,
                                       audio: audio, text: self.growingEdge(text), at: nanos))
            }

            self.partialText = text
            self.partialLagMs = lagMs

            if self.interactive { self.drawStatus() }
        }
    }

    /// A committed segment. Always scrolls, and resets the partial baseline.
    func final(_ text: String, lagMs: Int?, audio: ClosedRange<Double>?, at nanos: UInt64) {
        queue.async {
            let words = text.split(separator: " ").count
            self.partialText = ""
            self.partialLagMs = nil
            self.lastPartialWords = 0
            self.commit(self.trace(kind: "final", delta: words, lagMs: lagMs,
                                   audio: audio, text: text, at: nanos))
        }
    }

    // MARK: - rendering

    /// One scrolling line, columns aligned so cadence can be read vertically.
    ///
    /// `+Nms` is the gap since the previous event — the number that says whether
    /// tokens dribble or clump. `Δ` is words added by this arrival. `lag` is
    /// signed on purpose: a negative value means the analyzer reported audio
    /// ahead of what we have fed it, which is a clock disagreement worth seeing
    /// rather than a zero worth hiding.
    private func trace(
        kind: String,
        delta: Int,
        lagMs: Int?,
        audio: ClosedRange<Double>?,
        text: String,
        at nanos: UInt64
    ) -> String {
        let elapsed = Double(nanos &- startedNanos) / 1_000_000_000
        let gap = lastEventNanos.map { Int((nanos &- $0) / 1_000_000) }
        lastEventNanos = nanos

        let gapField = gap.map { String(format: "%+6dms", $0) } ?? "      ··"
        // A missing lag is printed as missing. Rendering "no measurement" as
        // "+0ms" is how the first version of this tool told a flat lie about
        // being live, and it cost a session's worth of trust in the numbers.
        let lagField = lagMs.map { String(format: "%+6dms", $0) } ?? "    ····"
        let window = audio.map { String(format: " audio %7.2f–%7.2f", $0.lowerBound, $0.upperBound) }
            ?? String(repeating: " ", count: 22)

        return String(
            format: "[%8.3fs] %-5@ %@  Δ%+3d  lag %@%@  %@",
            elapsed, kind as NSString, gapField as NSString, delta,
            lagField as NSString, window as NSString, text as NSString
        )
    }

    /// The tail of a hypothesis — where new words appear. Showing the head
    /// would push the interesting end off the right of the terminal.
    private func growingEdge(_ text: String, keep: Int = 52) -> String {
        guard text.count > keep else { return text }

        return "…" + String(text.suffix(keep))
    }

    /// Write a scrolling line, stepping around the status line if one is up.
    private func commit(_ line: String) {
        var out = ""

        if interactive && statusOnScreen {
            out += clearLine
            statusOnScreen = false
        }

        put(out + line + "\n")

        if interactive { drawStatus() }
    }

    /// Redraw the bottom line: level meter, then the live hypothesis. Truncated
    /// to the terminal so a long partial never wraps and eats scrollback.
    private func drawStatus() {
        guard interactive else { return }

        let db = Double(levelCentiDb.withLock { $0 }) / 100

        // Rise instantly, fall at ~40 dB/sec.
        heldDb = max(db, heldDb - Self.decayPerTickDb)

        var body = meter(heldDb) + String(format: " %6.1f dB", db)

        if partialText.isEmpty {
            body += "   ·  listening"
        } else {
            let lag = partialLagMs.map { String(format: "%+6dms", $0) } ?? "    ····"
            body += "   lag \(lag)  " + partialText
        }

        put(clearLine + truncate(body, to: columns()))
        statusOnScreen = true
    }

    /// A 20-cell bar over the useful range. Below -60 dBFS is silence for our
    /// purposes; clipping pins at the top rather than overflowing.
    private func meter(_ db: Double) -> String {
        let width = 20
        let filled = max(0, min(width, Int(((db + 60) / 60) * Double(width))))

        return "[" + String(repeating: "▌", count: filled)
            + String(repeating: "·", count: width - filled) + "]"
    }

    private let clearLine = "\r\u{1B}[2K"

    private func truncate(_ s: String, to width: Int) -> String {
        guard width > 1, s.count > width else { return s }

        return String(s.prefix(width - 1)) + "…"
    }

    private func columns() -> Int {
        var size = winsize()

        if ioctl(STDERR_FILENO, UInt(TIOCGWINSZ), &size) == 0, size.ws_col > 0 {
            return Int(size.ws_col) - 1
        }

        return 100
    }

    /// Straight at the descriptor. `write(2)` can return short, so loop.
    private func put(_ s: String) {
        let bytes = Array(s.utf8)

        bytes.withUnsafeBufferPointer { buffer in
            guard var pointer = buffer.baseAddress else { return }
            var remaining = buffer.count

            while remaining > 0 {
                let written = Darwin.write(STDERR_FILENO, pointer, remaining)

                if written <= 0 { return }

                pointer += written
                remaining -= written
            }
        }
    }
}
