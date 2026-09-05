// swift-tools-version: 6.0
import PackageDescription

// Sonocles — on-device speech-to-text that streams recognised words, live, to
// whatever is listening.
//
// Three products from one core:
//
//   SonoclesCore  the engine, capture, clock and transports. No UI, no
//                 terminal, no assumptions about who is consuming.
//   sonocles-cli  the measurement instrument. Every latency claim about this
//                 project came out of it and can be re-run from it.
//   Sonocles      the menu bar app.
//
// macOS 14 is the floor because that is what Parakeet on Core ML needs. The
// Apple engine is gated to 26 and is kept only as a baseline to measure
// against — see Docs/ENGINES.md for why it is not the default.
let package = Package(
    name: "Sonocles",
    platforms: [.macOS("14.0")],
    products: [
        .library(name: "SonoclesCore", targets: ["SonoclesCore"]),
        .executable(name: "sonocles-cli", targets: ["sonocles-cli"]),
        .executable(name: "Sonocles", targets: ["Sonocles"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.6")
    ],
    targets: [
        .target(
            name: "SonoclesCore",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
        .executableTarget(name: "sonocles-cli", dependencies: ["SonoclesCore"]),
        .executableTarget(name: "Sonocles", dependencies: ["SonoclesCore"]),
        .testTarget(name: "SonoclesCoreTests", dependencies: ["SonoclesCore"]),
    ]
)
