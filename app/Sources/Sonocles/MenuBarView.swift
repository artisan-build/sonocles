import SonoclesCore
import SwiftUI

/// The popover behind the menu bar icon.
///
/// Laid out around the one question someone opens it to ask: *is this hearing
/// me, right now.* So the meter and the live hypothesis get the space, the
/// numbers that qualify them sit directly underneath, and everything else —
/// engine, endpoints, the pairing token — is settled once and then ignored.
///
/// The centre panel has three states and shows exactly one. An idle meter
/// pinned at silence looks broken, and a meter shown during a model download
/// looks broken *and* is irrelevant, since nothing is listening yet. Each state
/// gets its own panel rather than one panel that lies in two of them.
///
/// Styled as sonocles.com is: limestone ground, ink, the terracotta signature,
/// and a 4 pt terracotta rule along the top — the foot of the site's colonnade
/// — so the popover and the site open the same way. Dark is for the live
/// transcript only, the way the site's stream of frames is dark on the
/// limestone page: it is the one thing here that is data rather than chrome.
struct MenuBarView: View {
    @Bindable var model: SidecarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Brand.terracotta).frame(height: 4)
            header
            rule
            centre
            rule
            controls
            strip
        }
        .frame(width: 344)
        .background(Brand.ground)
    }

    private var rule: some View {
        Rectangle().fill(Brand.line).frame(height: 1)
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 9) {
            SonoclesMark(progress: model.running ? 1 : 0.34)
                .foregroundStyle(model.running ? Brand.terracotta : Brand.script)
                .frame(width: 19, height: 19)
                .animation(.easeOut(duration: 0.25), value: model.running)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Sonocles")
                    .font(Type.wordmark(15))
                    .foregroundStyle(Brand.ink)
                Text("so-NOK-leez")
                    .font(Type.mono(9))
                    .foregroundStyle(Brand.inkFaint)
            }

            Spacer()

            StatePill(label: stateLabel, colour: stateColour)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var stateLabel: String {
        if model.preparation != nil { return "Preparing" }
        return model.running ? "Listening" : "Idle"
    }

    private var stateColour: Color {
        if model.preparation != nil { return Brand.terracottaInk }
        return model.running ? Brand.olive : Brand.script
    }

    // MARK: - centre

    /// The transcript is data and sits on the dark block; the other two
    /// states are prose and sit on the inset, like the site's cards.
    private var showingTranscript: Bool {
        model.preparation == nil && model.running
    }

    @ViewBuilder private var centre: some View {
        Group {
            if let preparation = model.preparation {
                preparing(preparation)
            } else if model.running {
                listening
            } else {
                idle
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(showingTranscript ? Brand.Block.panel : Brand.inset)
    }

    /// The first launch fetches ~220 MB and compiles it for the Neural Engine.
    /// Tens of seconds in which a meter reading silence would imply a fault
    /// where there is none.
    private func preparing(_ preparation: Preparation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preparation.summary)
                .font(Type.body(12))
                .foregroundStyle(Brand.inkSoft)

            // A bar only where the fraction is real. Compiling has no
            // measurable progress, so it gets a pulse instead — animating a bar
            // to look busy would be the same lie as reporting an unmeasured
            // latency as zero, and the brand notes say as much out loud.
            if let fraction = preparation.fraction {
                ProgressBar(fraction: fraction)
            } else {
                WorkingPulse()
            }

            Text("One time only — the models cache on disk.")
                .font(Type.body(10))
                .foregroundStyle(Brand.inkFaint)
        }
        .frame(height: Self.centreHeight, alignment: .center)
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 11) {
            LevelMeter(db: model.heldDb, reading: model.levelDb)

            transcript

            HStack(spacing: 16) {
                stat("lag", model.lagMs.map { "\($0) ms" })
                stat("every", model.gapMs.map { "\($0) ms" })
                Spacer()
            }
        }
        .frame(height: Self.centreHeight, alignment: .top)
    }

    /// The centre panel's height, the same in every state, so switching
    /// between them never moves the controls.
    static let centreHeight: CGFloat = 112
    /// Four lines of the transcript's mono at 12 pt.
    private static let transcriptHeight: CGFloat = 64

    /// The last few lines, newest at the bottom.
    ///
    /// A fixed window, so an arriving word never shoves the rest of the
    /// popover down — at five frames a second that would be a twitch, not an
    /// interface. Settled utterances sit dim above the live line, which is
    /// the one being revised and the one to watch; what no longer fits
    /// leaves off the top, faded rather than cut. Empty, it says what will
    /// happen rather than looking broken.
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.transcript.isEmpty && model.text.isEmpty {
                Text("Words appear here as you say them.")
                    .font(Type.mono(12))
                    .foregroundStyle(Brand.script)
            } else {
                ForEach(Array(model.transcript.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(Type.mono(12))
                        .foregroundStyle(Brand.Block.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.text.isEmpty {
                    Text(model.text)
                        .font(Type.mono(12))
                        .foregroundStyle(Brand.Block.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.transcriptHeight, alignment: .bottomLeading)
        .clipped()
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.14)],
                startPoint: .top, endPoint: .bottom)
        )
        .animation(nil, value: model.text)
        .animation(nil, value: model.transcript)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not listening")
                .font(Type.body(12, .medium))
                .foregroundStyle(Brand.ink)
            Text(
                "The stream stays open — anything can start it, including "
                    + "a POST to /start."
            )
            .font(Type.body(10.5))
            .foregroundStyle(Brand.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: Self.centreHeight, alignment: .center)
    }

    /// A missing measurement reads as "··", never as zero. Rendering absence as
    /// a number is how an earlier build spent a session insisting it was
    /// real-time while measuring nothing at all.
    private func stat(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Type.mono(10))
                .foregroundStyle(Brand.Block.dim)
            Text(value ?? "··")
                .font(Type.mono(11))
                .foregroundStyle(value == nil ? Brand.script : Brand.Block.terracotta)
        }
    }

    // MARK: - controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 11) {
            // The engine, as a segmented control drawn from shapes. A menu
            // `Picker` is AppKit-backed and `ImageRenderer` cannot rasterise
            // it, so every design review of this popover had a yellow box
            // where the picker was. The full name sits beside the label
            // because four full names do not fit in 316 pt. Only the engines
            // this Mac can run are offered — the same list `GET /engine`
            // answers as `available` — so Apple is not a segment on macOS 15.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Engine")
                        .font(Type.body(11))
                        .foregroundStyle(Brand.inkFaint)
                    Spacer()
                    Text(model.engineLabel)
                        .font(Type.mono(9.5))
                        .foregroundStyle(Brand.script)
                }
                Segmented(
                    options: EngineChoice.available.map { ($0, Self.short($0)) },
                    selection: Binding(get: { model.engine }, set: { model.use($0) }))

                // When to choose it, in one line that follows the selection.
                Text(Self.guidance(model.engine))
                    .font(Type.body(10.5))
                    .foregroundStyle(Brand.inkFaint)
                    .lineLimit(1)
                    .padding(.top, 1)
            }

            // Endpoints, not switches. The sockets bind at launch and stay up
            // for the life of the app, which is what lets POST /start work
            // while this popover says "Idle". Who is on them comes from the
            // same count `/status` reports as `clients`.
            HStack(spacing: 8) {
                endpoint("HTTP", ":\(model.httpPort)")
                dot
                endpoint("WS", ":\(model.wsPort)")
                dot
                Text(Self.clients(model.clients))
                    .font(Type.mono(10))
                    .foregroundStyle(model.clients == nil ? Brand.script : Brand.inkFaint)
                Spacer()
            }

            // Always open. The token is the one thing a new client needs
            // from this popover, and a disclosure hid it behind a click that
            // nobody knew to make.
            VStack(alignment: .leading, spacing: 7) {
                Text("Control API")
                    .font(Type.body(11))
                    .foregroundStyle(Brand.inkFaint)
                pairing
            }

            HStack(spacing: 8) {
                // Start is the site's button; Stop is the family's record red.
                // Preparing greys it to script, the colour of a thing that is
                // not there yet, and disables it.
                PillButton(
                    model.running ? "Stop" : "Start listening",
                    colour: model.preparation != nil
                        ? Brand.script : model.running ? Brand.oxide : Brand.terracottaDeep,
                    filled: true
                ) {
                    model.running ? model.stop() : model.start()
                }
                .disabled(model.preparation != nil)

                Spacer()

                PillButton("Quit", colour: Brand.terracottaInk, filled: false) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// The process, in one dark line under everything: which build this
    /// is, which engine it is set to, and how long the sockets have been up
    /// — what `GET /` and `/status` would say, so a screenshot of the
    /// popover is a bug report. The dot is lit while the sockets are bound.
    private var strip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.uptime == nil ? Brand.script : Brand.Block.terracotta)
                .frame(width: 5, height: 5)
            Text("sonocles \(model.version)")
                .foregroundStyle(Brand.Block.text)
            Text("·")
            if let uptime = model.uptime {
                Text(model.engine.label)
                Text("·")
                Text("up \(Self.uptime(uptime))")
            } else {
                // No uptime means no sockets: nothing to name an engine or
                // a duration for, so say that rather than a row of ··.
                Text("engine not running")
                    .foregroundStyle(Brand.script)
            }
        }
        .lineLimit(1)
        .font(Type.mono(9.5))
        .foregroundStyle(Brand.Block.dim)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Brand.Block.panel)
    }

    /// `41s`, `12m`, `1h 12m`, `2d 3h`: the two largest units that are not
    /// zero, the way a person says it.
    static func uptime(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let days = total / 86400
        let hours = total % 86400 / 3600
        let minutes = total % 3600 / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total % 60)s"
    }

    /// The bearer token, which every route on both sockets is behind. Shown
    /// masked; copied in full for a client that cannot read the file itself.
    private var pairing: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                "Every route is behind this token, the event stream included. Apps "
                    + "running as you read the file; rotating cuts every paired client off."
            )
            .font(Type.body(10))
            .foregroundStyle(Brand.inkFaint)
            .fixedSize(horizontal: false, vertical: true)

            Text(model.tokenFile)
                .font(Type.mono(10))
                .foregroundStyle(Brand.script)
                .lineLimit(1)
                .truncationMode(.middle)

            // The full token does not fit on one line at this width, so it
            // wraps when shown; masked, it is one short line. A missing token
            // — the sockets not yet bound — reads in the colour of absence.
            Text((model.tokenShown ? model.token : model.maskedToken) ?? "··")
                .font(Type.mono(11))
                .foregroundStyle(model.token == nil ? Brand.script : Brand.ink)
                .lineLimit(model.tokenShown ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .modifier(FieldChrome())

            HStack(spacing: 8) {
                PillButton(
                    model.tokenShown ? "Hide" : "Show",
                    colour: model.token == nil ? Brand.script : Brand.terracottaInk,
                    filled: false, compact: true
                ) {
                    model.tokenShown.toggle()
                }
                .disabled(model.token == nil)

                PillButton(
                    "Copy", colour: model.token == nil ? Brand.script : Brand.terracottaInk,
                    filled: false, compact: true
                ) {
                    model.copyToken()
                }
                .disabled(model.token == nil)

                Spacer()

                // Armed, it turns oxide and fills: the second click is the
                // one that cuts every paired client off.
                PillButton(
                    model.rotateArmed ? "Really rotate" : "Rotate",
                    colour: model.token == nil
                        ? Brand.script : model.rotateArmed ? Brand.oxide : Brand.terracottaInk,
                    filled: model.rotateArmed, compact: true
                ) {
                    model.rotateToken()
                }
                .disabled(model.token == nil)
            }
        }
    }

    /// What each engine is for, from the numbers in docs/ENGINES.md and the
    /// library's own notes on its chunk sizes: 160 ms arrives ~180 ms behind
    /// live; 320 ms is ~540 ms behind with a longer chunk that hears more
    /// context per pass (fewer misheard words, by the library's word-error
    /// figures); 1280 ms is the longest chunk; Apple delivers in ~3.8 s
    /// bursts. Nothing here that was not measured or documented.
    static func guidance(_ choice: EngineChoice) -> String {
        switch choice {
        case .fluid160: "About 180 ms behind you. The default — for cues and prompting."
        case .fluid320: "More context, fewer misheard words; half a second behind."
        case .fluid1280: "The most context, over a second behind — captions, not cues."
        case .apple: "Apple's on-device recogniser. Words arrive in bursts, ~4 s apart."
        }
    }

    /// Segment labels: what distinguishes the engines, and nothing else.
    private static func short(_ choice: EngineChoice) -> String {
        switch choice {
        case .fluid160: "160 ms"
        case .fluid320: "320 ms"
        case .fluid1280: "1280 ms"
        case .apple: "Apple"
        }
    }

    /// Singular, plural, or none; `··` until the sockets are bound.
    static func clients(_ count: Int?) -> String {
        switch count {
        case nil: "·· clients"
        case 0: "no clients"
        case 1: "1 client"
        case let n?: "\(n) clients"
        }
    }

    private var dot: some View {
        Text("·")
            .font(Type.mono(10))
            .foregroundStyle(Brand.script)
    }

    private func endpoint(_ label: String, _ port: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Type.mono(10))
                .foregroundStyle(Brand.script)
            Text(port)
                .font(Type.mono(10))
                .foregroundStyle(Brand.inkFaint)
        }
    }
}

/// Twenty cells over the useful range.
///
/// Below -60 dBFS is silence for our purposes and clipping pins at the top, so
/// the bar reads the way a console meter does. The numeric readout carries the
/// detail the bar throws away — a quiet room floor sits at the bottom of the
/// bar but still moves the number, which is what proves the microphone is live
/// when nobody is speaking.
///
/// Drawn on the dark block, in the block's own colours.
struct LevelMeter: View {
    let db: Double
    let reading: Double

    private var filled: Int {
        max(0, min(20, Int(((db + 60) / 60) * 20)))
    }

    var body: some View {
        HStack(spacing: 7) {
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(colour(for: index))
                        .frame(height: 13)
                }
            }

            Text(reading <= -119 ? "––" : String(format: "%.0f", reading))
                .font(Type.mono(10))
                .foregroundStyle(reading <= -119 ? Brand.script : Brand.Block.text)
                .frame(width: 24, alignment: .trailing)

            Text("dB")
                .font(Type.mono(9))
                .foregroundStyle(Brand.Block.dim)
        }
    }

    /// Terracotta through the working range, oxide at the top — the family's
    /// record red, so a hot signal reads here the way a REC light does in
    /// the prompter.
    private func colour(for index: Int) -> Color {
        guard index < filled else { return Brand.Block.field }

        return index >= 18 ? Brand.oxide : Brand.Block.terracotta
    }
}

/// A determinate bar, drawn rather than borrowed.
///
/// The system's linear `ProgressView` is AppKit-backed, which means it neither
/// matches the meter sitting a few points above it nor survives offscreen
/// rendering — so the design could not be reviewed without a human looking at a
/// screen. Twenty points of rounded rectangle solves both.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Brand.sink)
                Capsule()
                    .fill(Brand.terracotta)
                    .frame(width: max(3, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// Work with no measurable progress.
///
/// Deliberately not a bar. A bar implies a fraction, and compiling does not have
/// one — so this pulses to say "still going" without implying how far along it
/// is, which is the only honest thing available.
struct WorkingPulse: View {
    @State private var bright = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Brand.terracotta)
                    .frame(width: 5, height: 5)
                    .opacity(bright ? 0.95 : 0.25)
                    .animation(
                        .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: bright
                    )
            }
            Spacer()
        }
        .frame(height: 5)
        .onAppear { bright = true }
    }
}

/// The site's pill button, drawn from shapes.
///
/// A system `Button` in a bordered style is AppKit-backed and neither matches
/// the panel nor survives `ImageRenderer` — so the design could not be
/// reviewed without a human at a screen. A capsule and a label solve both.
struct PillButton: View {
    let label: String
    let colour: Color
    let filled: Bool
    /// Row-sized: for controls that sit beside a pill, not in a bar.
    var compact = false
    let action: () -> Void

    init(
        _ label: String, colour: Color, filled: Bool, compact: Bool = false,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.colour = colour
        self.filled = filled
        self.compact = compact
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Type.body(compact ? 9.5 : 11, .semibold))
                .foregroundStyle(filled ? Brand.ground : colour)
                .padding(.horizontal, compact ? 8 : 12)
                .padding(.vertical, compact ? 2.5 : 5)
                .background(Capsule().fill(filled ? colour : .clear))
                .overlay(Capsule().strokeBorder(colour, lineWidth: filled ? 0 : 1.2))
        }
        .buttonStyle(.plain)
    }
}

/// A choice drawn from shapes: the site's pill, split into equal segments.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(Type.body(11, .semibold))
                        .foregroundStyle(on ? Brand.ground : Brand.terracottaInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(on ? Brand.terracottaDeep : .clear)
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Brand.terracottaInk, lineWidth: 1.2))
    }
}

/// A text field's frame, drawn, so it sits on limestone the way the site's
/// install chip does rather than in the system's rounded border.
struct FieldChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Brand.ground))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.line, lineWidth: 1))
    }
}
