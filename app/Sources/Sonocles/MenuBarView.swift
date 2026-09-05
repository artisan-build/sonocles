import SonoclesCore
import SwiftUI

/// The popover behind the menu bar icon.
///
/// Laid out around the one question someone opens it to ask: *is this hearing
/// me, right now.* So the meter and the live hypothesis get the space, the
/// numbers that qualify them sit directly underneath, and everything else —
/// engine, endpoints, credentials — is settled once and then ignored.
///
/// The centre panel has three states and shows exactly one. An idle meter
/// pinned at silence looks broken, and a meter shown during a model download
/// looks broken *and* is irrelevant, since nothing is listening yet. Each state
/// gets its own panel rather than one panel that lies in two of them.
struct MenuBarView: View {
    @Bindable var model: SidecarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Brand.field).frame(height: 1)
            centre
            Rectangle().fill(Brand.field).frame(height: 1)
            controls
        }
        .frame(width: 344)
        .background(Brand.panel)
    }

    // MARK: - header

    private var header: some View {
        HStack(spacing: 9) {
            SonoclesMark(progress: model.running ? 1 : 0.34)
                .foregroundStyle(model.running ? Brand.stress : Brand.ghost)
                .frame(width: 19, height: 19)
                .animation(.easeOut(duration: 0.25), value: model.running)

            Text("Sonocles")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Brand.bright)
                .kerning(0.2)

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
        if model.preparation != nil { return Brand.stress }
        return model.running ? Brand.quote : Brand.ghost
    }

    // MARK: - centre

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
        .background(Brand.ink)
    }

    /// The first launch fetches ~220 MB and compiles it for the Neural Engine.
    /// Tens of seconds in which a meter reading silence would imply a fault
    /// where there is none.
    private func preparing(_ preparation: Preparation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(preparation.summary)
                .font(.system(size: 12))
                .foregroundStyle(Brand.body)

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
                .font(.system(size: 10))
                .foregroundStyle(Brand.script)
        }
        .frame(height: 92, alignment: .center)
    }

    private var listening: some View {
        VStack(alignment: .leading, spacing: 11) {
            LevelMeter(db: model.heldDb, reading: model.levelDb)

            // Height is reserved so an arriving word never shoves the rest of
            // the popover down — at five frames a second that would be a twitch,
            // not an interface.
            Text(model.text.isEmpty ? "Listening…" : model.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(model.text.isEmpty ? Brand.script : Brand.body)
                .lineLimit(3, reservesSpace: true)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: model.text)

            HStack(spacing: 16) {
                stat("lag", model.lagMs.map { "\($0) ms" })
                stat("every", model.gapMs.map { "\($0) ms" })
                Spacer()
            }
        }
        .frame(height: 92, alignment: .top)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Not listening")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Brand.faint)
            Text(
                "The stream stays open — anything can start it, including "
                    + "a POST to /start."
            )
            .font(.system(size: 10.5))
            .foregroundStyle(Brand.script)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(height: 92, alignment: .center)
    }

    /// A missing measurement reads as "··", never as zero. Rendering absence as
    /// a number is how an earlier build spent a session insisting it was
    /// real-time while measuring nothing at all.
    private func stat(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Brand.script)
            Text(value ?? "··")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(value == nil ? Brand.script : Brand.stress)
        }
    }

    // MARK: - controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("Engine")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.faint)

                Spacer()

                Picker("", selection: Binding(get: { model.engine }, set: { model.use($0) })) {
                    ForEach(EngineChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 182)
            }

            // Endpoints, not switches. The sockets bind at launch and stay up
            // for the life of the app, which is what lets POST /start work
            // while this popover says "Idle".
            HStack(spacing: 15) {
                endpoint("HTTP", ":7357")
                endpoint("WS", ":7358")
                Spacer()
            }

            DisclosureGroup {
                credentials
            } label: {
                Text("Control API")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.faint)
            }

            HStack(spacing: 8) {
                Button(model.running ? "Stop" : "Start listening") {
                    model.running ? model.stop() : model.start()
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.stress)
                .disabled(model.preparation != nil)

                Spacer()

                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.faint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var credentials: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(
                "Protects /start, /stop and /status. The event stream stays "
                    + "open — EventSource cannot send an Authorization header, and "
                    + "credentials in a URL would be worse than a loopback-only read."
            )
            .font(.system(size: 10))
            .foregroundStyle(Brand.script)
            .fixedSize(horizontal: false, vertical: true)

            TextField("username", text: $model.username)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            SecureField("password — blank leaves the API open", text: $model.password)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))

            HStack {
                StatePill(
                    label: model.authEnabled ? "Locked" : "Open",
                    colour: model.authEnabled ? Brand.quote : Brand.stress
                )

                Spacer()

                Button("Save") { model.saveCredentials() }
                    .font(.system(size: 11))
            }
        }
        .padding(.top, 7)
    }

    private func endpoint(_ label: String, _ port: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Brand.script)
            Text(port)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Brand.ghost)
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
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(reading <= -119 ? Brand.script : Brand.faint)
                .frame(width: 24, alignment: .trailing)

            Text("dB")
                .font(.system(size: 9))
                .foregroundStyle(Brand.script)
        }
    }

    /// Amber through the working range, red at the top, using the prompter's
    /// own key so a hot signal reads here the way a REC light does there.
    private func colour(for index: Int) -> Color {
        guard index < filled else { return Brand.field }

        return index >= 18 ? Brand.rec : Brand.stress
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
                Capsule().fill(Brand.field)
                Capsule()
                    .fill(Brand.stress)
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
                    .fill(Brand.stress)
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
