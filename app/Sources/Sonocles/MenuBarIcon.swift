import AppKit
import SwiftUI

/// The menu bar icon, rasterised from the mark as a template image.
///
/// A SwiftUI view handed straight to `MenuBarExtra`'s label does not work here,
/// for two reasons that compound. It inherits no foreground style in that
/// context, so a shape drawn with bare `fill()` and `stroke()` renders with no
/// colour at all — the app launches, takes a menu bar slot, and appears to be
/// missing entirely. And even coloured explicitly it would be *a* colour, which
/// is wrong: the menu bar inverts between light and dark, and anything that is
/// not a template image stays put while everything around it flips.
///
/// So the mark is rendered once to an `NSImage` with `isTemplate = true`.
/// macOS then uses only the alpha channel and tints it to match the bar. The
/// dimmed idle state survives that, because the dimming is opacity — which is
/// alpha, which is exactly what a template keeps.
@MainActor
enum MenuBarIcon {
    static let listening = render(dimmed: false)
    static let idle = render(dimmed: true)

    static func image(listening isListening: Bool) -> NSImage {
        isListening ? listening : idle
    }

    /// 18pt is the conventional menu bar glyph size; rendering at 2x and
    /// declaring the point size keeps it crisp on Retina without doubling on
    /// non-Retina.
    /// Idle dims the whole mark rather than individual arcs.
    ///
    /// Per-arc dimming reads clearly at 64pt in a design review and not at all
    /// at 18pt in a menu bar, which is the only size that matters. Overall
    /// alpha is what every other menu bar item does, and it survives being
    /// glanced at from across a room.
    private static func render(dimmed: Bool) -> NSImage {
        let side: CGFloat = 18

        let renderer = ImageRenderer(
            content:
                SonoclesMark(lineWidth: 1.5)
                .foregroundStyle(.black)
                .opacity(dimmed ? 0.4 : 1)
                .frame(width: side, height: side)
        )
        renderer.scale = 2

        guard let image = renderer.nsImage else {
            // Never expected, but an invisible menu bar item is precisely the
            // failure this file exists to prevent, so fall back to something
            // that definitely draws.
            let fallback =
                NSImage(
                    systemSymbolName: "dot.radiowaves.right", accessibilityDescription: "Sonocles")
                ?? NSImage()
            fallback.isTemplate = true
            return fallback
        }

        image.size = NSSize(width: side, height: side)
        image.isTemplate = true

        return image
    }
}
