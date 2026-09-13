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
            if model.uptime == nil {
                down
            } else {
                centre
                rule
                controls
            }
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
        if model.uptime == nil { return "Down" }
        if model.preparation != nil { return "Preparing" }
        return model.running ? "Listening" : "Idle"
    }

    private var stateColour: Color {
        if model.uptime == nil { return Brand.oxide }
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

    /// The lower half: two sections and a button row, each under a kicker
    /// and between hairline rules — the way Rheocles' settings are set,
    /// and what docs/BRAND.md calls furniture. Nothing here is a bare sans
    /// label; the three text styles are the kicker, the block's mono and
    /// the help body, all of which the popover already used.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            engineSection
            rule
            connectedApps
            rule
            buttons
        }
    }

    /// The engine, in the words of the person choosing it: first the model —
    /// Parakeet on the Neural Engine, or Apple's recogniser — with one line
    /// saying what it is; then, for Parakeet, the speed, three rows each
    /// with what it costs and what it is for. The rows are the control, so
    /// what a switch means is read before the click that costs a download.
    private var engineSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            kicker("Engine")
                .padding(.bottom, 2)
            Segmented(
                options: Self.models.map { ($0, $0.family) },
                selection: Binding(
                    get: { model.engine == .apple ? .apple : model.chunk },
                    set: { model.use($0) }),
                value: { Self.about($0) })
            Text(Self.about(model.engine))
                .font(Type.body(10))
                .foregroundStyle(Brand.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            if model.engine != .apple {
                kicker("Speed", colour: Brand.script)
                    .padding(.top, 4)
                speeds
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 12)
    }

    /// The model picker's options: Parakeet stands for whichever chunk was
    /// last used; Apple only where this Mac can run it.
    private static var models: [EngineChoice] {
        EngineChoice.apple.isAvailable ? [.fluid160, .apple] : [.fluid160]
    }

    /// Which speed row the pointer is over, so it reads in ink before it
    /// is chosen.
    @State private var hovered: EngineChoice?

    /// The Parakeet chunks as rows: the speed, then one sentence. The
    /// selected row in ink behind a 3 pt accent bar, as Rheocles marks an
    /// armed stream; the others in ink-faint until hovered. Each row is a
    /// button, and posts the same switch a segment used to.
    private var speeds: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(EngineChoice.parakeet, id: \.self) { choice in
                let on = choice == model.engine
                let lit = on || choice == hovered
                Button {
                    model.use(choice)
                } label: {
                    HStack(spacing: 11) {
                        // The bar sits on the popover's edge; the label
                        // lands on the text margin.
                        Rectangle()
                            .fill(on ? Brand.terracotta : .clear)
                            .frame(width: 3, height: 11)
                        Text(choice.chunk ?? "")
                            .font(Type.mono(10, on ? .medium : .regular))
                            .frame(width: 44, alignment: .leading)
                        Text(Self.tradeoff(choice))
                            .font(Type.body(10))
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(lit ? Brand.ink : Brand.inkFaint)
                    .frame(height: 15)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.spokenChunk(choice))
                .accessibilityHint(Self.tradeoff(choice))
                .accessibilityAddTraits(on ? .isSelected : [])
                .onHover { inside in
                    if inside {
                        hovered = choice
                    } else if hovered == choice {
                        hovered = nil
                    }
                }
            }
        }
        .padding(.leading, -14)
    }

    /// Who is connected, and how an app connects: the key, with what Copy
    /// and Rotate do to it; the two ports, each with the one thing it is
    /// for. Every word for someone who has never heard "bearer".
    private var connectedApps: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                kicker("Connected apps")
                Spacer()
                Text(Self.apps(model.clients))
                    .font(Type.body(10))
                    .foregroundStyle(model.clients == nil ? Brand.script : Brand.ink)
            }

            HStack(spacing: 6) {
                Text("Key")
                    .font(Type.body(10))
                    .foregroundStyle(Brand.ink)
                    .padding(.trailing, 2)

                // A missing key — the sockets not yet bound — reads in the
                // colour of absence. VoiceOver keeps the protocol's word.
                Text(model.maskedToken ?? "··")
                    .font(Type.mono(11))
                    .foregroundStyle(model.token == nil ? Brand.script : Brand.ink)
                    .lineLimit(1)
                    .textSelection(.enabled)
                    .modifier(FieldChrome())
                    .accessibilityLabel("bearer token")

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

                Spacer(minLength: 0)

                // Armed, it turns oxide and fills: the second click is the
                // one that disconnects everything.
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

            if model.tokenShown, let token = model.token {
                Text(token)
                    .font(Type.mono(11))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .modifier(FieldChrome())
                    .accessibilityLabel("bearer token")
            }

            (Text(
                "The key an app needs to connect — Copy it into the app. Rotate makes a "
                    + "new key and disconnects everything. Apps on this Mac can also read it from "
            )
            .font(Type.body(10))
                + Text(model.tokenFileAbbreviated).font(Type.mono(10))
                + Text(".").font(Type.body(10)))
                .foregroundStyle(Brand.inkFaint)
                .fixedSize(horizontal: false, vertical: true)

            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 2) {
                port("HTTP API", model.httpPort, "where apps ask Sonocles things")
                port("WebSocket", model.wsPort, "the live word stream")
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 12)
    }

    /// One port: what it is called, its number, and the one thing it is for.
    private func port(_ label: String, _ number: UInt16, _ what: String) -> some View {
        GridRow {
            Text(label)
                .font(Type.body(10))
                .foregroundStyle(Brand.ink)
            Text(":\(String(number))")
                .font(Type.mono(10))
                .foregroundStyle(Brand.ink)
            Text(what)
                .font(Type.body(10))
                .foregroundStyle(Brand.inkFaint)
        }
        .lineLimit(1)
    }

        private var buttons: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - down

    /// The sockets are not up, so nothing below the header is true: no
    /// port is listening, no POST can start anything, the token is not
    /// there. One panel says so — the reason, and the one action there is
    /// — in place of everything the controls would otherwise promise.
    private var down: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                kicker("Engine")
                Text("down")
                    .font(Type.mono(11))
                    .foregroundStyle(Brand.oxide)
            }
            Text(model.downReason ?? "The sockets are not up.")
                .font(Type.body(10.5))
                .foregroundStyle(Brand.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            HStack {
                PillButton("Relaunch", colour: Brand.terracottaDeep, filled: true) {
                    model.relaunch()
                }
                Spacer()
                PillButton("Quit", colour: Brand.terracottaInk, filled: false) {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Brand.inset)
    }

    // MARK: - strip

    /// The process, in one dark line under everything: which build, which
    /// model at which speed, and how many apps — what `GET /` and `/status`
    /// would say, in the sections' own words, so a screenshot of the
    /// popover is a bug report. The dot is olive while listening and script
    /// when nothing is bound.
    private var strip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(
                    model.uptime == nil
                        ? Brand.script : model.running ? Brand.olive : Brand.Block.dim
                )
                .frame(width: 5, height: 5)
            Text("sonocles \(model.version)")
                .foregroundStyle(Brand.Block.text)
            Text("·")
            if model.uptime == nil {
                Text("engine not running")
                    .foregroundStyle(Brand.script)
            } else {
                Text(model.engine.family)
                Text("·")
                if let chunk = model.engine.chunk {
                    Text(chunk)
                    Text("·")
                }
                Text(Self.apps(model.clients, short: true))
                    .foregroundStyle(model.clients == nil ? Brand.script : Brand.Block.dim)
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

    // MARK: - engine facts

    /// What the selected model is, in one sentence — the line under the
    /// picker. Parakeet streams as you speak; Apple's engine delivers in
    /// bursts a few seconds apart (docs/ENGINES.md measures 3.7 s).
    static func about(_ choice: EngineChoice) -> String {
        switch choice {
        case .fluid160, .fluid320, .fluid1280:
            "Runs on this Mac's Neural Engine. Words arrive as you speak."
        case .apple:
            "Apple's own recogniser. Words arrive in bursts, a few seconds apart."
        }
    }

    /// What each speed costs and is for, in one sentence and no other
    /// numbers: 160 ms is the fastest (docs/ENGINES.md: ~180 ms behind
    /// live), 320 ms trades a beat for steadier words (fewer revisions per
    /// word, and the library's lower word-error rate at the longer chunk),
    /// 1280 ms is the longest chunk and the most context per pass.
    static func tradeoff(_ choice: EngineChoice) -> String {
        switch choice {
        case .fluid160: "Fastest. For prompters and cues."
        case .fluid320: "Steadier words, a beat later."
        case .fluid1280: "Most accurate. For captions and transcripts."
        case .apple: ""
        }
    }

    /// The speed as VoiceOver should say it.
    static func spokenChunk(_ choice: EngineChoice) -> String {
        switch choice {
        case .fluid160: "160 milliseconds"
        case .fluid320: "320 milliseconds"
        case .fluid1280: "1280 milliseconds"
        case .apple: "Apple"
        }
    }

    /// How many apps are connected, in words: the section's value, or the
    /// strip's shorter form; `··` until the sockets are bound.
    static func apps(_ count: Int?, short: Bool = false) -> String {
        let n: String
        switch count {
        case nil: n = "·· apps"
        case 0: n = "no apps"
        case 1: n = "1 app"
        case let c?: n = "\(c) apps"
        }
        return short || count == nil ? n : "\(n) connected"
    }

    /// A section label: mono, uppercase, letterspaced, in the accent —
    /// furniture, never competing with what sits beneath.
    private func kicker(_ label: String, colour: Color = Brand.terracottaInk) -> some View {
        Text(label.uppercased())
            .font(Type.kicker())
            .kerning(1.1)
            .foregroundStyle(colour)
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
///
/// Each segment carries `value` as its accessibility value, so a VoiceOver
/// user hears what the choice is before making it.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var value: (Value) -> String = { _ in "" }

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
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(self.value(value))
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
