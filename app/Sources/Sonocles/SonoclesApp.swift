import AppKit
import SonoclesCore
import SwiftUI

/// The menu bar app.
///
/// `MenuBarExtra` in `.window` style — the popover-from-the-icon shape rather
/// than a list of menu items, which is the right frame for something whose main
/// job is a live meter and a line of moving text.
///
/// `LSUIElement` in the bundle's Info.plist keeps it out of the Dock and the app
/// switcher. That plist is also what gives the app a stable TCC identity: run as
/// a bare executable, microphone permission attaches to whatever terminal
/// launched it, which is why the original spike needed you to grant Terminal mic
/// access by hand. A signed bundle gets its own entry.
@main
struct SonoclesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = SidecarModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            // The mark itself, so the icon in the menu bar and the one in the
            // popover are the same drawing. Lit while listening, dimmed while
            // idle, so state reads without opening anything.
            SonoclesMark(progress: model.running ? 1 : 0.34, lineWidth: 1.35)
                .frame(width: 17, height: 17)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Binds the sockets at launch.
///
/// This cannot live in the popover's `onAppear`: a `MenuBarExtra` in window
/// style does not build its content until someone clicks the icon, so the
/// control API would not exist until a human had already opened the thing it is
/// meant to spare them opening.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            // A design feedback loop that needs no human and no screen
            // recording permission. Renders every popover state and exits.
            if Preview.renderIfRequested() {
                NSApplication.shared.terminate(nil)
                return
            }

            SidecarModel.shared.bind()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in SidecarModel.shared.shutdown() }
    }
}
