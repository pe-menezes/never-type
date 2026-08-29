// swift-tools-version: 6.0
import PackageDescription

// The logic lives in NeverTypeCore so it can be tested: an executable target
// cannot be imported by a test target. The executable is left as just the
// shell that assembles the menu bar and wires the pieces together.
let package = Package(
    name: "NeverType",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
        .target(
            name: "NeverTypeCore",
            dependencies: ["CWhisper"],
            linkerSettings: [
                // Static, not the Homebrew dylibs.
                //
                // The hardened runtime turns on library validation, which
                // refuses to load a dylib signed by another team — and that
                // refusal is precisely what closes code injection into a
                // process that holds Accessibility. With dynamic linking
                // against Homebrew the two are incompatible, and the app died
                // in dyld.
                //
                // As a bonus: the .app stops requiring Homebrew on the machine
                // of whoever uses it, and does not break if whisper-cpp is
                // uninstalled.
                //
                // Produced by scripts/build-app.sh. See vendor/whisper.
                .unsafeFlags([
                    "-Lvendor/whisper/lib",
                    "-lwhisper", "-lggml", "-lggml-base", "-lggml-cpu",
                    "-lggml-metal", "-lggml-blas",
                    "-lc++",
                    "-framework", "Foundation",
                    "-framework", "Metal",
                    "-framework", "MetalKit",
                    "-framework", "Accelerate",
                ])
            ]),
        .executableTarget(name: "NeverType", dependencies: ["NeverTypeCore"]),
        .testTarget(name: "NeverTypeCoreTests", dependencies: ["NeverTypeCore"]),
    ]
)
