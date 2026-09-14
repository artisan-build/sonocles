import SonoclesCore
import Testing

@testable import Sonocles

/// The engine picker is two levels over four engine ids: the model, then
/// for Parakeet the chunk. What can go wrong is the mapping — a Parakeet
/// segment that only matches one chunk reads as unselected at the others,
/// and posts the default instead of the speed that was set.
@Suite("Engine picker")
struct EnginePickerTests {
    private let all: [EngineChoice] = [.fluid160, .fluid320, .fluid1280, .apple]

    @Test("the Parakeet segment is the chunk in use, so it is selected at any speed")
    func parakeetSegmentIsTheChunk() {
        for chunk in EngineChoice.parakeet {
            let options = MenuBarView.models(chunk: chunk, available: all)
            #expect(options == [chunk, .apple])
            // The selection the picker reads for a Parakeet engine is the chunk;
            // the segment holds it, so `on` is true.
            #expect(options.contains(chunk))
        }
    }

    @Test("Apple is a segment only where this Mac can run it")
    func appleOnlyWhereAvailable() {
        #expect(
            MenuBarView.models(chunk: .fluid320, available: EngineChoice.parakeet) == [.fluid320])
        #expect(MenuBarView.models(chunk: .fluid320, available: all) == [.fluid320, .apple])
        // A chunk that is not a chunk falls back to the default rather than
        // offering Apple twice.
        #expect(MenuBarView.models(chunk: .apple, available: all) == [.fluid160, .apple])
    }

    @Test("choosing Parakeet after Apple posts the speed that was set")
    @MainActor
    func parakeetAfterAppleRemembersTheChunk() {
        let model = SidecarModel()
        model.engine = .fluid1280
        model.engine = .apple
        #expect(model.chunk == .fluid1280)
        // The Parakeet segment carries that chunk, so selecting it is a
        // switch to 1280 ms, not to the default.
        #expect(MenuBarView.models(chunk: model.chunk, available: all).first == .fluid1280)
        model.engine = .fluid320
        #expect(model.chunk == .fluid320)
    }
}
