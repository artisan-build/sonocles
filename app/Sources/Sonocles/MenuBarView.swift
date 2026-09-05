import SonoclesCore
import SwiftUI

/// The popover behind the menu bar icon.
///
/// Laid out around the one question someone opens it to ask: is this actually
/// hearing me, right now. So the meter and the live hypothesis get the space,
/// the numbers that qualify them sit directly underneath, and everything else —
/// engine, ports, transport — is settled once and then ignored.
///
/// The meter is deliberately not decorative. It is driven from the audio
/// thread's own peak readings, independent of the model, which splits an
/// ambiguous silence into two answers: meter alive and text dead means capture
/// is fine and the engine is late; both dead means check the microphone.
struct MenuBarView: View {
    @Bindable var model: SidecarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Brand.field)
            live
            Divider().overlay(Brand.field)
            controls
        }
        .frame(width: 340)
        .background(Brand.panel)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.running ? Brand.quote : Brand.ghost)
                .frame(width: 7, height: 7)

            Text("Sonocles")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Brand.bright)

            Spacer()

            Text(model.status)
                .font(.system(size: 11))
                .foregroundStyle(Brand.faint)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 10) {
            LevelMeter(db: model.heldDb, reading: model.levelDb)

            // Reserves its own height so an arriving word does not shove the
            // rest of the popover downward on every hypothesis.
            Text(model.text.isEmpty ? "…" : model.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(model.text.isEmpty ? Brand.script : Brand.body)
                .lineLimit(3, reservesSpace: true)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                stat("lag", model.lagMs.map { "\($0) ms" })
                stat("every", model.gapMs.map { "\($0) ms" })
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Brand.ink)
    }

    /// A missing measurement reads as "··", never as zero. Rendering absence as
    /// a number is how an earlier build of this spent a session insisting it
    /// was real-time when it had simply measured nothing.
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Engine")
                    .font(.system(size: 11))
                    .foregroundStyle(Brand.faint)

                Spacer()

                Picker(
                    "",
                    selection: Binding(
                        get: { model.engine },
                        set: { model.use($0) }
                    )
                ) {
                    ForEach(EngineChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 178)
            }

            // Endpoints, not switches. The sockets bind at launch and stay up
            // for the life of the app, which is what lets POST /start work
            // while this popover reads "Idle".
            HStack(spacing: 14) {
                endpoint("HTTP", ":7357")
                endpoint("WS", ":7358")
                Spacer()
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 7) {
                    Text(
                        "Protects /start, /stop and /status. The event stream stays open — EventSource cannot send an Authorization header, and credentials in a URL would be worse than a loopback-only read."
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
                        Circle()
                            .fill(model.authEnabled ? Brand.quote : Brand.stress)
                            .frame(width: 6, height: 6)
                        Text(model.authEnabled ? "Locked" : "Open")
                            .font(.system(size: 10))
                            .foregroundStyle(Brand.faint)

                        Spacer()

                        Button("Save") { model.saveCredentials() }
                            .font(.system(size: 11))
                    }
                }
                .padding(.top, 6)
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
/// Below -60 dBFS is silence for our purposes and clipping pins at the top
/// rather than overflowing, so the bar reads the way a console meter does. The
/// numeric readout carries the detail the bar throws away — a quiet room floor
/// sits at the bottom of the bar but still moves the number, which is what
/// proves the microphone is live when nobody is speaking.
struct LevelMeter: View {
    let db: Double
    let reading: Double

    private var filled: Int {
        max(0, min(20, Int(((db + 60) / 60) * 20)))
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(0..<20, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(colour(for: i))
                        .frame(height: 14)
                }
            }

            Text(reading <= -119 ? "  --" : String(format: "%.0f", reading))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Brand.faint)
                .frame(width: 26, alignment: .trailing)

            Text("dB")
                .font(.system(size: 9))
                .foregroundStyle(Brand.script)
        }
    }

    private func colour(for index: Int) -> Color {
        guard index < filled else { return Brand.field }

        // Amber through the working range, red at the top, using the prompter's
        // own key so a hot signal reads the same here as a REC light does there.
        return index >= 18 ? Brand.rec : Brand.stress
    }
}
