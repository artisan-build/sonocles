import AppKit
import SonoclesCore
import SwiftUI

/// Renders the popover to PNGs and exits.
///
///     Sonocles.app/Contents/MacOS/Sonocles --render-preview <directory>
///
/// A design feedback loop that does not need a human. Every state the popover
/// can be in gets written out, including the ones that are awkward to reach by
/// hand — a model download at 43%, a hot input level, an empty transcript — so
/// the layout can be judged in the states it will actually be seen in rather
/// than only the state it happens to be in right now.
///
/// One known limitation: `ImageRenderer` cannot rasterise AppKit-backed
/// controls, and draws them as a filled accent rectangle with a "no entry"
/// glyph instead. Nothing here uses one any more — the progress bar, the
/// buttons, the field chrome and the engine picker are all drawn from
/// shapes for exactly this reason — and anything added later that does will
/// show up that way in these PNGs before it shows up on a screen.
@MainActor
enum Preview {
    static func renderIfRequested() -> Bool {
        let arguments = CommandLine.arguments

        guard let flag = arguments.firstIndex(of: "--render-preview"),
            flag + 1 < arguments.count
        else { return false }

        let directory = URL(fileURLWithPath: arguments[flag + 1])
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)

        for (name, view) in states() {
            write(view, to: directory.appendingPathComponent("\(name).png"))
        }

        write(marks(), to: directory.appendingPathComponent("mark.png"))

        // The menu bar icon, on both grounds it has to survive. An icon that
        // renders empty is invisible rather than wrong, which is the hardest
        // kind of broken to notice.
        for (name, listening) in [("menubar-listening", true), ("menubar-idle", false)] {
            let icon = MenuBarIcon.image(listening: listening)
            write(
                HStack(spacing: 20) {
                    ForEach([Color.black, Color.white], id: \.self) { ground in
                        Image(nsImage: icon)
                            .renderingMode(.template)
                            .foregroundStyle(ground == .black ? Color.white : Color.black)
                            .frame(width: 34, height: 34)
                            .padding(10)
                            .background(ground)
                    }
                }
                .padding(16)
                .background(Color.gray),
                to: directory.appendingPathComponent("\(name).png"))
        }

        return true
    }

    /// A token of the real shape, so the masked and the shown forms are
    /// judged at their real widths.
    private static let token =
        "3f9a1c77e2b04d5f8a6c1e2d9b7f4a0c5d6e7f8091a2b3c4d5e6f70819a2b3c4"

    private static func states() -> [(String, AnyView)] {
        [
            (
                "idle",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.token = token
                            $0.clients = 0
                        }))
            ),
            (
                "idle-1280",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.engine = .fluid1280
                            $0.token = token
                            $0.clients = 1
                        }))
            ),
            // Apple: no speed rows, and the model line carries the cost.
            (
                "idle-apple",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.engine = .apple
                            $0.token = token
                            $0.clients = 1
                        }))
            ),
            (
                "listening",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.running = true
                            $0.token = token
                            $0.clients = 2
                            $0.levelDb = -21.4
                            $0.heldDb = -21.4
                            $0.transcript = [
                                "welcome back everyone",
                                "the agenda is short today",
                            ]
                            $0.text =
                                "and this week we are looking at the two proposals that landed"
                            $0.lagMs = 180
                            $0.gapMs = 206
                        }))
            ),
            (
                "listening-quiet",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.running = true
                            $0.token = token
                            $0.clients = 1
                            $0.levelDb = -54
                            $0.heldDb = -54
                        }))
            ),
            // The sockets did not bind: the down panel in place of the
            // controls, and a strip that says so.
            (
                "down",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.uptime = nil
                            $0.clients = nil
                            $0.token = nil
                            $0.downReason =
                                "Could not bind the sockets: port 7357 is already in use."
                        }))
            ),
            (
                "pairing-rotate-armed",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.tokenShown = true
                            $0.rotateArmed = true
                            $0.token = token
                            $0.clients = 3
                        }))
            ),
            (
                "preparing",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.token = token
                            $0.preparation = .downloading(fraction: 0.43, file: 11, of: 16)
                        }))
            ),
            (
                "compiling",
                AnyView(
                    MenuBarView(
                        model: configured {
                            $0.token = token
                            $0.preparation = .compiling(model: "streaming_encoder")
                        }))
            ),
        ]
    }

    /// The mark at the sizes it is actually used, on both grounds it appears on.
    private static func marks() -> AnyView {
        AnyView(
            HStack(spacing: 22) {
                ForEach([17, 19, 34, 64], id: \.self) { size in
                    VStack(spacing: 8) {
                        SonoclesMark(lineWidth: size <= 20 ? 1.35 : 2.4)
                            .foregroundStyle(Brand.terracotta)
                            .frame(width: CGFloat(size), height: CGFloat(size))
                        SonoclesMark(progress: 0.34, lineWidth: size <= 20 ? 1.35 : 2.4)
                            .foregroundStyle(Brand.script)
                            .frame(width: CGFloat(size), height: CGFloat(size))
                        Text("\(size)")
                            .font(Type.mono(8))
                            .foregroundStyle(Brand.script)
                    }
                }
            }
            .padding(22)
            .background(Brand.ground)
        )
    }

    /// Every bound state has an uptime; the previews get a plausible one so
    /// the strip is judged with a real value in it.
    private static func configured(_ change: (SidecarModel) -> Void) -> SidecarModel {
        let model = SidecarModel()
        model.version = version
        model.uptime = 4_335
        // Bound sockets always have a count; a state that shows `··` here
        // is one the app cannot be in.
        model.clients = 0
        // Never the real path: these PNGs go on the site and the social
        // card, and the real one names whoever rendered them.
        model.tokenFile = "~/Library/Application Support/Sonocles/token"
        change(model)
        return model
    }

    /// A bare executable has no Info.plist and reports `dev`, which is true
    /// and useless on a site. SONOCLES_VERSION stamps the previews the way
    /// VERSION stamps the bundle in Scripts/bundle.sh; the site's og.html
    /// says how to set it.
    private static var version: String {
        ProcessInfo.processInfo.environment["SONOCLES_VERSION"] ?? Service.version
    }

    private static func write(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        // Two, so the rendering matches what a Retina display shows and the
        // hairlines are judged at the density they will be seen at.
        renderer.scale = 2

        guard let image = renderer.nsImage,
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        try? png.write(to: url)
    }
}
