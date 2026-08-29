// swift-tools-version: 6.0
import PackageDescription

// A lógica vive em NeverTypeCore para poder ser testada: um alvo executável não
// é importável por um alvo de teste. O executável fica sendo só a casca que
// monta a menu bar e liga os pedaços.
let package = Package(
    name: "NeverType",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(name: "CWhisper", path: "Sources/CWhisper"),
        .target(
            name: "NeverTypeCore",
            dependencies: ["CWhisper"],
            linkerSettings: [
                // Estático, e não as dylibs do Homebrew.
                //
                // O hardened runtime liga validação de bibliotecas, que recusa
                // carregar dylib assinada por outra equipe — e é justamente
                // essa recusa que fecha a injeção de código num processo que
                // detém Acessibilidade. Com linkagem dinâmica contra o Homebrew
                // as duas coisas são incompatíveis, e o app morria no dyld.
                //
                // De quebra: o .app deixa de exigir Homebrew na máquina de quem
                // for usar, e não quebra se o whisper-cpp for desinstalado.
                //
                // Produzido por scripts/build-app.sh. Ver vendor/whisper.
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
