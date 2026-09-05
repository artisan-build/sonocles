import Foundation

/// What the engine is doing before it can listen.
///
/// The first launch fetches about 220 MB from Hugging Face and then compiles it
/// for the Neural Engine, which is tens of seconds of a menu bar icon doing
/// nothing. Without this the only honest thing the UI could say was "Starting…",
/// which is indistinguishable from hung.
///
/// Compiling is reported separately from downloading on purpose: it is the
/// phase with no network activity and no obvious progress, so it is the one
/// most likely to be mistaken for a stall.
public enum Preparation: Sendable, Equatable {
    /// Asking the repository what files exist.
    case listing
    /// Fetching weights. `fraction` is over the whole download, not the file.
    case downloading(fraction: Double, file: Int, of: Int)
    /// Compiling Core ML models after the fetch.
    case compiling(model: String)
    /// Models resident; capture can start.
    case ready

    /// A line fit for a status field or a terminal.
    public var summary: String {
        switch self {
        case .listing:
            return "Finding model files…"
        case .downloading(let fraction, let file, let total):
            let percent = Int((fraction * 100).rounded())
            return total > 0
                ? "Downloading model — \(percent)% (file \(file) of \(total))"
                : "Downloading model — \(percent)%"
        case .compiling(let model):
            return "Compiling \(model) for the Neural Engine…"
        case .ready:
            return "Models resident"
        }
    }

    /// Fraction complete where one is known.
    ///
    /// Nil during compiling rather than a fabricated number: the phase has no
    /// measurable progress, and inventing one to keep a bar moving is the same
    /// class of lie as reporting an unmeasured latency as zero.
    public var fraction: Double? {
        switch self {
        case .listing: return nil
        case .downloading(let fraction, _, _): return fraction
        case .compiling: return nil
        case .ready: return 1
        }
    }

    public var isFinished: Bool { self == .ready }
}
