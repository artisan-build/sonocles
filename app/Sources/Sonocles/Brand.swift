import AppKit
import SwiftUI

/// The palette, by role.
///
/// `docs/BRAND.md` is the source and names the pigments; this file names the
/// roles so a view never says "terracotta" and a palette change stays here.
/// The popover is sonocles.com: limestone ground, ink text, the terracotta
/// signature, olive for listening, oxide for a hot signal, script for a value
/// we do not have. Dark is for the data block only — the live transcript and
/// its numbers — the way the site's stream and code blocks are dark on the
/// limestone page.
///
/// An earlier version of this file was Pteroprompter's dark theme with the
/// pigments swapped, and the popover read as a third product. Rheocles
/// settled the fix — one palette, both surfaces — and this copies it.
enum Brand {
    // ground — the plaster
    static let ground = Color(hex: 0xFAF2E4)
    static let inset = Color(hex: 0xEFE5D2)
    static let sink = Color(hex: 0xE0D4BE)
    static let line = Color(hex: 0xDED0B8)

    // ink
    static let ink = Color(hex: 0x2A211A)
    static let inkSoft = Color(hex: 0x4E4034)
    static let inkFaint = Color(hex: 0x6B5C4C)

    // the signature — fired clay on limestone
    /// Fills, rules and marks: large, or carrying no text. 4.0:1 on
    /// limestone, which is why it is not used for small type.
    static let terracotta = Color(hex: 0xC4552E)
    /// The signature as text — links, kickers, numbers. Same hue, far enough
    /// down to 5.4:1 on limestone.
    static let terracottaInk = Color(hex: 0xA8431F)
    /// The signature as a button ground: 5.5:1 under white, 5.0:1 under
    /// limestone.
    static let terracottaDeep = Color(hex: 0xB2461F)

    // states — a small language the icon and the popover both speak
    /// Listening, healthy, go.
    static let olive = Color(hex: 0x6E7A52)
    /// Hot signal, recording, stop.
    static let oxide = Color(hex: 0xB4453A)
    /// A value we do not have. Load-bearing beyond its name: a missing
    /// latency, an unmeasured level, an empty transcript. Absence gets its
    /// own colour so it is never mistaken for a number.
    static let script = Color(hex: 0x7A6A59)

    /// The dark block on the light page — the site's `pre` and `.stream`,
    /// and here the live transcript. Nowhere else.
    enum Block {
        /// The site draws these on `--ink`; so does this.
        static let panel = ink
        /// An empty meter cell. The one token the site does not have,
        /// because the site has no meter.
        static let field = Color(hex: 0x3B2F27)
        static let text = Color(hex: 0xEDE4D6)
        static let dim = Color(hex: 0x9E8F7C)
        /// The signature on a dark block — the site's `--terracotta-soft`,
        /// which it uses for exactly this and nothing on limestone.
        static let terracotta = Color(hex: 0xDD7A4E)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// Type roles, in the family's faces.
///
/// Fraunces, Instrument Sans and IBM Plex Mono — the same three the site
/// loads from Google — ship in the bundle under the OFL (`Fonts/`, licences
/// beside them) and are registered for this process at launch. Fraunces is
/// used the way the site uses it: `SOFT 30`, `WONK 1`, weight 700, so the
/// wordmark reads as drawn rather than defaulted. Every role falls back to
/// the system face of the same character if registration fails, because a
/// popover with no text is worse than one in the wrong font.
enum Type {
    static func wordmark(_ size: CGFloat) -> Font {
        variable(
            "Fraunces", size: size,
            axes: [Axis.weight: 700, Axis.soft: 30, Axis.wonk: 1, Axis.opticalSize: 24],
            fallback: .system(size: size, weight: .bold, design: .serif))
    }
    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        variable(
            "Instrument Sans", size: size, axes: [Axis.weight: Self.wght(weight)],
            fallback: .system(size: size, weight: weight))
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name = weight == .regular ? "IBMPlexMono-Regular" : "IBMPlexMono-Medium"
        guard registered, let nsFont = NSFont(name: name, size: size) else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return Font(nsFont)
    }
    /// Kickers: mono, uppercase, letterspaced — furniture, never competing
    /// with what sits beneath.
    static func kicker(_ size: CGFloat = 9) -> Font {
        mono(size, .medium)
    }

    /// OpenType variation axis tags, as CoreText wants them.
    private enum Axis {
        static let weight: UInt32 = 0x7767_6874  // wght
        static let soft: UInt32 = 0x534F_4654  // SOFT
        static let wonk: UInt32 = 0x574F_4E4B  // WONK
        static let opticalSize: UInt32 = 0x6F70_737A  // opsz
    }

    private static func wght(_ weight: Font.Weight) -> Double {
        switch weight {
        case .medium: 500
        case .semibold: 600
        case .bold, .heavy, .black: 700
        default: 400
        }
    }

    private static func variable(
        _ family: String, size: CGFloat, axes: [UInt32: Double], fallback: Font
    ) -> Font {
        guard registered else { return fallback }
        var variation: [NSNumber: NSNumber] = [:]
        for (tag, value) in axes { variation[NSNumber(value: tag)] = NSNumber(value: value) }
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): variation,
        ])
        guard let nsFont = NSFont(descriptor: descriptor, size: size),
            nsFont.familyName == family
        else { return fallback }
        return Font(nsFont)
    }

    /// Register every face in `Fonts/` for this process, once. In the bundle
    /// that is `Contents/Resources/Fonts`; straight out of `swift build` it
    /// is the source directory, so `--render-preview` renders in the real
    /// faces on the machine that built it.
    static let registered: Bool = {
        let candidates = [
            Bundle.main.resourceURL?.appending(path: "Fonts"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fonts"),
        ]
        guard
            let directory = candidates.compactMap({ $0 }).first(where: {
                FileManager.default.fileExists(atPath: $0.path)
            }),
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return false }

        var any = false
        for url in files where url.pathExtension == "ttf" {
            // An "already registered" error is fine; a face is a face.
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) { any = true }
        }
        return any
    }()
}
