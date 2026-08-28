import CWhisper
import Foundation

/// Onde o modelo mora depois de instalado.
public enum ModelStore {
    public static let fileName = "ggml-large-v3-turbo-q5_0.bin"

    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FalaFlow/models")
    }

    public static var modelURL: URL { directory.appendingPathComponent(fileName) }

    /// Piso de tamanho, em bytes. O menor candidato quantizado tem 181 MB.
    ///
    /// O magic sozinho não basta, e a lacuna é grave: um arquivo truncado começa
    /// com os 4 bytes certos, o whisper.cpp aceita como "modelo vazio para
    /// teste" e devolve um contexto **válido** — e a primeira inferência mata o
    /// processo com `std::out_of_range`, exceção de C++ que nenhum `try` do
    /// Swift intercepta. O app não avisa nada: simplesmente não abre.
    ///
    /// O equivalente em shell (`is_valid_ggml`, em setup-bench.sh) já exigia
    /// magic **e** tamanho. Esta regra estava em um lado e não no outro.
    public static let minimumBytes = 50 * 1024 * 1024

    /// O magic do ggml é gravado como uint32 little-endian, então os bytes no
    /// arquivo saem invertidos: `6c6d6767`, que lido como texto vira "lmgg", não
    /// "ggml". Checar o texto direto reprova todo modelo válido — erro já
    /// cometido neste projeto.
    public static func isValid(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let size else { return false }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let magic = (try? handle.read(upToCount: 4)) ?? Data()
        return isValid(magic: magic, size: size)
    }

    /// A regra em si, separada da leitura de disco.
    ///
    /// Assim dá para testar o piso de tamanho sem escrever 50 MB a cada execução
    /// da suíte.
    public static func isValid(magic: Data, size: Int) -> Bool {
        guard size >= minimumBytes else { return false }
        guard magic.count == 4 else { return false }
        return magic.map { String(format: "%02x", $0) }.joined() == "6c6d6767"
    }
}

public enum TranscriberError: Error, CustomStringConvertible {
    case modelMissing(URL)
    case modelInvalid(URL)
    case contextFailed
    case inferenceFailed(Int32)

    public var description: String {
        switch self {
        case .modelMissing(let u):
            return "modelo não encontrado em \(u.path). Rode scripts/fetch-model.sh"
        case .modelInvalid(let u):
            return "o arquivo em \(u.path) não é um modelo ggml completo (truncado ou corrompido). Rode scripts/fetch-model.sh"
        case .contextFailed:
            return "não consegui carregar o modelo na memória"
        case .inferenceFailed(let code):
            return "a transcrição falhou (código \(code))"
        }
    }
}

/// Transcreve áudio localmente, com o modelo carregado uma vez e mantido quente.
///
/// Não é seguro para uso concorrente: o contexto do whisper.cpp é de uso serial.
/// Quem usa serializa — no app, uma fila dedicada.
public final class Transcriber {
    private let context: OpaquePointer
    public private(set) var backend: String = ""

    public init(modelURL: URL = ModelStore.modelURL) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw TranscriberError.modelMissing(modelURL)
        }
        guard ModelStore.isValid(modelURL) else {
            throw TranscriberError.modelInvalid(modelURL)
        }

        // `ggml_backend_load_all()` foi removido daqui.
        //
        // Ela varre o diretório do executável **e o diretório de trabalho atual**
        // procurando `libggml-<nome>-*.so` para dar `dlopen`. Com linkagem
        // dinâmica ela era necessária; com o build estático os três backends já
        // vêm registrados pelo construtor do registro do ggml — a auditoria
        // provou com uma sonda que não a chama e mesmo assim lista MTL, BLAS e
        // CPU. Hoje o hardened runtime bloqueia a carga, mas a chamada só abria
        // superfície sem entregar nada: uma linha de entitlement a mais e viraria
        // execução de código arbitrário num processo que detém Acessibilidade.
        //
        // A verificação abaixo é o que garante que o Metal está mesmo ativo.

        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let ctx = whisper_init_from_file_with_params(modelURL.path, params) else {
            throw TranscriberError.contextFailed
        }
        context = ctx

        // Enumera os dispositivos que o ggml de fato registrou, em vez de
        // procurar a palavra "metal" em log — que foi o falso negativo pego na
        // auditoria da Parte 1: um log de execução em CPU contém dezenas de
        // linhas com "metal", vindas da enumeração do device.
        var devices: [String] = []
        for i in 0..<ggml_backend_dev_count() {
            guard let dev = ggml_backend_dev_get(i) else { continue }
            devices.append(String(cString: ggml_backend_dev_name(dev)))
        }
        self.devices = devices
        self.usesMetal = devices.contains { $0.uppercased().contains("MTL") || $0.uppercased().contains("METAL") }
        backend = devices.joined(separator: ", ")
    }

    /// Dispositivos registrados pelo ggml.
    public private(set) var devices: [String] = []

    /// Se o aquecimento rodou com sucesso. Definido por quem chama `warmUp()`.
    public var warmedUp = false

    /// Se falso, a inferência roda em CPU — cerca de 11x mais lenta, medido.
    /// Não é aviso cosmético: é a diferença entre o app servir e não servir.
    public private(set) var usesMetal = false

    deinit { whisper_free(context) }

    /// Roda uma inferência descartável antes do primeiro ditado real.
    ///
    /// **A justificativa original estava errada e vale registrar.** O spike
    /// mediu 968 ms na primeira transcrição contra 664 ms na segunda e eu
    /// atribuí a diferença à compilação de pipelines do Metal. Um A/B da
    /// auditoria, em processos frios, mostrou o ganho real: ~25 ms (sem
    /// aquecimento 617–655 ms, com aquecimento 619–634 ms). Os 304 ms do spike
    /// eram outra coisa — o custo de verdade da "primeira vez" é o
    /// `ggml_metal_library_init`, medido em 6,4 s com o cache de shaders do SO
    /// frio, e ele acontece dentro do `init`, não aqui.
    ///
    /// Mantido mesmo assim: custa ~600 ms de prontidão em segundo plano, no
    /// lançamento, e compra ~25 ms no primeiro ditado. Barato, invisível, e o
    /// retorno agora diz se funcionou em vez de fingir.
    @discardableResult
    public func warmUp() -> Bool {
        let silence = [Float](repeating: 0, count: 16_000)
        do {
            _ = try transcribe(silence)
            return true
        } catch {
            return false
        }
    }

    public func transcribe(_ samples: [Float]) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.print_special = false
        params.no_timestamps = true
        params.n_threads = 4

        var text = ""
        var failure: Int32 = 0
        "pt".withCString { language in
            params.language = language
            let code = whisper_full(context, params, samples, Int32(samples.count))
            guard code == 0 else { failure = code; return }
            for i in 0..<whisper_full_n_segments(context) {
                text += String(cString: whisper_full_get_segment_text(context, i))
            }
        }
        guard failure == 0 else { throw TranscriberError.inferenceFailed(failure) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
