#if canImport(SwiftUI)
import SwiftUI

/// Sonocles' palette: limestone and terracotta.
///
/// Not Pteroprompter's. An earlier version of this file lifted that palette
/// verbatim and called it family resemblance, which was a generous word for
/// borrowing. The two are siblings and one consumes the other, but a tool
/// with its own name deserves its own colours.
///
/// Greek, but a temple rather than a museum case: pale limestone, fired
/// terracotta, a little olive and bronze. The site is illustrated in the same
/// key with flat comic drawings rather than photographed artifacts — an earlier
/// pass did the artifacts beautifully and produced a page that read like a
/// catalogue, which is a strange register for a 220 MB menu bar utility.
///
/// It stays dark for the same reason the prompter does. This sits over
/// whatever you are actually doing, frequently while a camera is running,
/// and should never flash white at you mid-take.
public enum Brand {
    /// Surfaces, darkest to lightest — the black slip.
    public static let slip = Color(hex: 0x100C0A)
    public static let ground = Color(hex: 0x16110E)
    public static let panel = Color(hex: 0x1C1611)
    public static let raised = Color(hex: 0x241C16)
    public static let field = Color(hex: 0x2B211A)

    /// Text, brightest to dimmest — the unpainted ground.
    public static let bone = Color(hex: 0xEFE3D0)
    public static let body = Color(hex: 0xCDBBA3)
    public static let muted = Color(hex: 0xB09B84)
    public static let faint = Color(hex: 0x9A8874)

    /// The colour of a value we do not have.
    ///
    /// Load-bearing beyond its name. A missing latency, an unmeasured level,
    /// an empty transcript. Absence gets its own colour so it is never
    /// mistaken for a number.
    public static let script = Color(hex: 0x6B5C4B)

    /// The signature. Fired clay.
    public static let terracotta = Color(hex: 0xC86F45)
    public static let terracottaBright = Color(hex: 0xE08A5C)

    /// Aged bronze — listening, healthy, go.
    public static let verdigris = Color(hex: 0x7FA88C)
    /// Ochre — attention without alarm.
    public static let ochre = Color(hex: 0xD9A441)
    /// Iron oxide — hot signal, recording, stop.
    public static let oxide = Color(hex: 0xB4453A)

    // MARK: - Roles
    //
    // Views name the job, not the pigment, so a palette change stays in this
    // file instead of spreading through the interface.

    public static let accent = terracotta
    public static let listening = verdigris
    public static let idle = script
    public static let hot = oxide
    public static let bright = bone
    public static let ghost = script
    public static let ink = ground
    public static let card = raised
    public static let stress = terracotta
    public static let quote = verdigris
    public static let rec = oxide
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
