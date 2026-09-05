#if canImport(SwiftUI)
import SwiftUI

/// Pteroprompter's palette, so the two read as one product.
///
/// Values are lifted verbatim from `pteroprompter.com/resources/css/app.css`
/// rather than eyeballed, because "close enough" across two codebases is how a
/// brand quietly drifts. The prompter's surface is deliberately dark in both
/// appearances, which suits a menu bar popover — it sits over whatever the user
/// is actually looking at and should not flash white at them mid-take.
public enum Brand {
    /// Surfaces, darkest to lightest.
    public static let screen = Color(hex: 0x0E0C09)
    public static let ink = Color(hex: 0x14110D)
    public static let panel = Color(hex: 0x171410)
    public static let card = Color(hex: 0x1C1813)
    public static let field = Color(hex: 0x1E1A15)

    /// Text, brightest to dimmest.
    public static let bright = Color(hex: 0xECE6DA)
    public static let body = Color(hex: 0xC9C1B2)
    public static let muted = Color(hex: 0xB3AA9A)
    public static let dim = Color(hex: 0xA39A89)
    public static let faint = Color(hex: 0x8F8674)
    public static let ghost = Color(hex: 0x7D7565)
    public static let script = Color(hex: 0x6F6656)

    /// The colour key the prompter teaches you as you read. Reused here for
    /// status rather than invented, so amber means the same thing in both.
    public static let stress = Color(hex: 0xF2B45C)
    public static let code = Color(hex: 0x8BC4F0)
    public static let aside = Color(hex: 0xEAA2BF)
    public static let quote = Color(hex: 0xA6CF9E)
    public static let rec = Color(hex: 0xE06666)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
#endif
