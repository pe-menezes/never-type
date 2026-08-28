import AppKit
import AVFoundation
import FalaFlowCore

/// Onde o áudio da última gravação fica. Um arquivo só, sobrescrito: a Parte 3
/// lê daqui, e o app não guarda histórico de nada que você falou.
private func lastRecordingURL() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("FalaFlow/last.wav")
}

/// Dono do modelo, carregado uma vez e mantido quente.
///
/// É um `actor` e não uma fila serial de propósito: o contexto do whisper.cpp é
/// de uso serial, e um ator faz o compilador garantir isso. Fila serial
/// dependeria de eu lembrar de sempre despachar por ela.
/// `Result` exige que a falha conforme a `Error`; uma String não conforma.
struct TranscriptionFailure: Error { let reason: String }

actor TranscriptionService {
    private var transcriber: Transcriber?
    private(set) var status: String = "modelo ainda não carregado"
    private(set) var metalActive = false
    private(set) var loadedOK = false
    private(set) var devices = ""

    func isMetalActive() -> Bool { metalActive }
    func didLoad() -> Bool { loadedOK }
    func deviceList() -> String { devices }

    /// Carrega e aquece. Chamado uma vez, no lançamento.
    func prepare() {
        let started = Date()
        do {
            let t = try Transcriber()
            let loaded = Int(Date().timeIntervalSince(started) * 1000)
            t.warmedUp = t.warmUp()
            let warmed = Int(Date().timeIntervalSince(started) * 1000)
            transcriber = t
            let warmedOK = t.warmedUp
            let gpu = t.usesMetal ? "Metal" : "CPU (LENTO)"
            status = "\(gpu) · carga \(loaded) ms · aquecimento \(warmed - loaded) ms"
                + (warmedOK ? "" : " (AQUECIMENTO FALHOU)")
            metalActive = t.usesMetal
            devices = t.backend
            loadedOK = true
        } catch {
            status = "\(error)"
        }
    }

    /// Devolve o erro real em vez de `nil`.
    ///
    /// A versão anterior usava `try?` e o delegate reportava o status de *carga
    /// do modelo* como se fosse a causa: com o modelo carregado e o whisper
    /// devolvendo código de erro, o usuário lia "transcrição indisponível:
    /// Metal · carga 168 ms" — uma mensagem que descreve saúde, não falha.
    func transcribe(_ samples: [Float]) -> Result<(text: String, ms: Int), TranscriptionFailure> {
        guard let transcriber else { return .failure(TranscriptionFailure(reason: status)) }
        let started = Date()
        do {
            let text = try transcriber.transcribe(samples)
            return .success((text, Int(Date().timeIntervalSince(started) * 1000)))
        } catch {
            return .failure(TranscriptionFailure(reason: "\(error)"))
        }
    }

    func currentStatus() -> String { status }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Criado em applicationDidFinishLaunching, não aqui.
    //
    // O construtor do delegate roda antes de `setActivationPolicy(.accessory)`,
    // e trocar a política de ativação depois de já existir um item na menu bar
    // faz o item ser descartado. O app segue vivo, o objeto responde
    // `isVisible = true` e `frame.width = 30`, e mesmo assim nada é desenhado.
    private var statusItem: NSStatusItem!
    private let monitor = HotkeyMonitor()
    private let recorder = AudioRecorder(destination: lastRecordingURL())
    private let menu = NSMenu()
    private let overlay = RecordingOverlay()
    private let transcription = TranscriptionService()
    private var modelStatus = "carregando modelo…"

    /// A última transcrição, guardada para o menu.
    ///
    /// Resolve uma tensão da spec: ela manda devolver o pasteboard depois de
    /// colar (educado) e também manda não perder a transcrição se não houver
    /// onde colar. As duas juntas se contradizem — devolver apaga o texto. E não
    /// dá para saber se a colagem chegou em algum lugar sem consultar a API de
    /// Acessibilidade, que está no anti-escopo.
    ///
    /// Então: devolve o pasteboard sempre, e o texto continua alcançável por
    /// aqui. Nada se perde, e o clipboard de ninguém é sequestrado.
    private var lastTranscript: String? {
        didSet { persistTranscript() }
    }

    private static var transcriptURL: URL {
        logURL.deletingLastPathComponent().appendingPathComponent("ultima-transcricao.txt")
    }

    /// Grava a última transcrição em disco.
    ///
    /// Guardar só em memória perdia o texto ao fechar o app — e o único caminho
    /// para recuperá-lo, quando a colagem não chega em lugar nenhum, é o menu.
    private func persistTranscript() {
        guard let lastTranscript else { return }
        try? lastTranscript.write(to: Self.transcriptURL, atomically: true, encoding: .utf8)
    }

    private func loadPersistedTranscript() {
        guard let text = try? String(contentsOf: Self.transcriptURL, encoding: .utf8),
              !text.isEmpty else { return }
        lastTranscript = text
    }

    /// Consultado ao sistema toda vez, em vez de guardado numa variável.
    ///
    /// A versão anterior guardava o estado numa flag preenchida durante o
    /// lançamento, e o menu era montado antes disso — então exibia "Microfone:
    /// faltando" com a permissão concedida e a gravação funcionando. Estado de
    /// permissão também muda por fora, nos Ajustes do Sistema, sem avisar o app.
    /// Perguntar é barato e nunca desatualiza.
    private var micAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uma instância só, com trava atômica.
        //
        // A versão anterior consultava `NSRunningApplication` e decidia — dois
        // passos, e o registro no LaunchServices é assíncrono. Em lançamentos
        // simultâneos as duas instâncias liam zero e as duas sobreviviam: a
        // auditoria reproduziu 3 de 3. O efeito não é cosmético — dois monitores
        // globais de tecla fazem um ditado virar duas gravações, duas
        // transcrições e dois ⌘V, e são 1,1 GB de modelo em memória.
        //
        // `flock` resolve num passo indivisível: quem pega, roda.
        guard Self.acquireInstanceLock() else {
            NSRunningApplication
                .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.falaflow.app")
                .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
                .activate()
            NSApp.terminate(nil)
            return
        }

        startLog()
        loadPersistedTranscript()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.idle)
        // O menu se remonta ao ser aberto (menuNeedsUpdate), então nunca mostra
        // estado velho.
        menu.delegate = self
        statusItem.menu = menu

        monitor.onEvent = { [weak self] event in self?.handle(event) }
        recorder.onError = { [weak self] message in
            self?.overlay.hide()
            self?.render(.blocked)
            self?.log(message)
        }
        monitor.start()

        requestMicrophoneAccess()
        warnIfAccessibilityMissing()

        // Carrega e aquece fora da main thread: são centenas de MB e uma
        // inferência descartável. Bloquear aqui congelaria a menu bar.
        Task {
            await transcription.prepare()
            let status = await transcription.currentStatus()
            self.modelStatus = status
            self.log("modelo: \(status)")
            // O aviso de Metal só cabe se o modelo carregou. Antes, modelo
            // ausente também disparava "sem Metal" — mandando quem fosse depurar
            // para o lado errado.
            if await self.transcription.didLoad() {
                self.log("dispositivos do ggml: \(await self.transcription.deviceList())")
                if await !self.transcription.isMetalActive() {
                    self.log("ATENÇÃO: sem Metal, a transcrição roda em CPU e fica ~11x mais lenta.")
                    self.render(.blocked)
                }
            } else {
                self.render(.blocked)
            }
        }
        log("pronto. trigger: \(monitor.trigger.label)")
    }

    // MARK: - Estados visuais

    private enum Visual { case idle, recording, blocked }

    private func render(_ state: Visual) {
        guard let button = statusItem.button else {
            log("SEM BOTÃO no status item — o ícone não tem onde ser desenhado")
            return
        }
        let symbol: String
        switch state {
        // A forma muda junto com a cor: contorno quando parado, preenchido
        // gravando, cortado quando bloqueado. Cor sozinha não serve como único
        // sinal de estado.
        case .idle:      symbol = "mic"
        case .recording: symbol = "mic.fill"
        case .blocked:   symbol = "mic.slash"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FalaFlow")
        if image == nil { log("símbolo '\(symbol)' não carregou") }
        // Sempre template.
        //
        // Imagem template é a que o macOS repinta conforme o fundo da barra;
        // sem isso o símbolo é desenhado na cor natural dele, preto, e some
        // contra a barra escura — o ícone ficava invisível exatamente enquanto
        // estava gravando. E `contentTintColor` só tinge imagem template, então
        // o vermelho que eu queria também não acontecia.
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = (state == .recording) ? .systemRed : nil
        // Fallback de largura: um item de largura variável só com imagem nula
        // fica com zero pixels e desaparece sem erro nenhum.
        button.title = (image == nil) ? "FF" : ""
        let tint = (state == .recording) ? "vermelho" : "padrão"
        log("ícone → \(symbol) (\(tint)), template=\(image?.isTemplate ?? false), largura=\(button.frame.width)")
    }

    // MARK: - Ciclo do ditado

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .pressed:
            guard micAuthorized else {
                render(.blocked)
                log("microfone não autorizado — ditado ignorado")
                return
            }
            do {
                try recorder.start()
                render(.recording)
                overlay.show()
            } catch {
                render(.blocked)
                log("falha ao iniciar gravação: \(error)")
            }
        case .released:
            let url = recorder.stop()
            overlay.hide()
            render(.idle)
            guard url != nil else { return }
            let samples = recorder.lastSamples
            log("gravado: \(samples.count) amostras (\(String(format: "%.1f", Double(samples.count) / 16_000)) s)")
            Task {
                switch await self.transcription.transcribe(samples) {
                case .success(let result):
                    self.log("transcrito em \(result.ms) ms → \(result.text)")
                    self.deliver(result.text)
                case .failure(let failure):
                    // Sinal visível: sem isto o ditado sumia em silêncio — o
                    // ícone já voltou ao normal, o app não tem janela, e o
                    // stderr não vai a lugar nenhum quando aberto pelo Finder.
                    self.log("TRANSCRIÇÃO FALHOU: \(failure.reason)")
                    self.render(.blocked)
                }
            }
        case .cancelled:
            recorder.cancel()
            overlay.hide()
            render(.idle)
            log("cancelado: tecla comum pressionada durante o hold")
        }
    }

    /// Coloca o texto onde o cursor está.
    private func deliver(_ text: String) {
        guard !text.isEmpty else {
            log("transcrição vazia — nada a inserir")
            return
        }
        lastTranscript = text

        switch TextInjector.insert(text) {
        case .inserted:
            break
        case .blockedBySecureInput:
            // Campo de senha em foco: o macOS descarta eventos sintéticos.
            // Tentar seria fingir que funcionou.
            log("campo de senha em foco — não inseri. O texto está no menu, em \"Copiar última transcrição\".")
            render(.blocked)
            flashIdle()
        case .failed(let reason):
            log("não consegui inserir: \(reason). O texto está no menu.")
            render(.blocked)
            flashIdle()
        }
    }

    /// Volta ao ícone normal depois de sinalizar um problema, para o app não
    /// ficar preso em estado de erro por causa de um ditado.
    private func flashIdle() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if !self.recorder.isRecording { self.render(.idle) }
        }
    }

    @objc private func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
        log("última transcrição copiada")
    }

    // MARK: - Permissões

    private func requestMicrophoneAccess() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            if !micAuthorized { render(.blocked) }
            return
        }
        // A API assíncrona, e não a de closure.
        //
        // Uma closure escrita dentro de um método `@MainActor` **herda** esse
        // isolamento por inferência, e o Swift insere uma checagem em runtime.
        // O callback do TCC chega numa fila de background, a checagem falha e o
        // processo morre — foi o que derrubou o app duas vezes. Trocar o corpo
        // por `Task { @MainActor in }` não resolvia: a checagem estoura na
        // closure externa, antes de chegar no corpo.
        //
        // Com `await` não existe closure para herdar isolamento, e a retomada
        // acontece na main actor por construção.
        Task { @MainActor in
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            self.render(granted ? .idle : .blocked)
        }
    }

    /// Sem Acessibilidade, os monitores globais não recebem evento nenhum — e não
    /// avisam. O app ficaria mudo parecendo quebrado, então isto é dito em voz alta.
    private func warnIfAccessibilityMissing() {
        guard !HotkeyMonitor.hasAccessibilityPermission else { return }
        render(.blocked)
        log("Acessibilidade não concedida: o trigger global não vai funcionar.")
        HotkeyMonitor.requestAccessibilityPermission()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        menu.removeAllItems()
        let acc = HotkeyMonitor.hasAccessibilityPermission
        menu.addItem(disabled("Trigger: \(monitor.trigger.label) (segure e fale)"))
        menu.addItem(.separator())
        menu.addItem(disabled("Microfone: \(micAuthorized ? "ok" : "faltando")"))
        menu.addItem(disabled("Acessibilidade: \(acc ? "ok" : "faltando")"))
        menu.addItem(disabled("Modelo: \(modelStatus)"))
        if let lastTranscript {
            menu.addItem(.separator())
            let preview = lastTranscript.count > 40
                ? String(lastTranscript.prefix(40)) + "…"
                : lastTranscript
            let copy = NSMenuItem(title: "Copiar última transcrição",
                                  action: #selector(copyLastTranscript), keyEquivalent: "")
            copy.target = self
            copy.toolTip = preview
            menu.addItem(copy)
        }
        if !acc {
            let fix = NSMenuItem(title: "Abrir Ajustes de Acessibilidade…",
                                 action: #selector(openAccessibilitySettings), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sair do FalaFlow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Diário do app.
    ///
    /// Escreve no stderr e num arquivo. Aberto pelo Finder, o stderr do app não
    /// vai para lugar nenhum — e foi por isso que três bugs seguidos (o ícone
    /// descartado, o crash na permissão e o ícone preto sobre fundo preto)
    /// tiveram que ser diagnosticados olhando a tela em vez de lendo log.
    /// Truncado a cada lançamento: é diagnóstico da sessão atual, não histórico.
    private func log(_ message: String) {
        let line = "falaflow: \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
        guard let handle = try? FileHandle(forWritingTo: Self.logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(line.utf8))
    }

    /// Mantido aberto pela vida do processo: fechar libera a trava.
    private nonisolated(unsafe) static var instanceLock: CInt = -1

    private static func acquireInstanceLock() -> Bool {
        let dir = logURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(".instance.lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        // Sem conseguir abrir a trava, melhor deixar o app rodar do que travar
        // por causa de um arquivo.
        guard fd >= 0 else { return true }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        instanceLock = fd
        return true
    }

    static let logURL = lastRecordingURL()
        .deletingLastPathComponent()
        .appendingPathComponent("falaflow.log")

    private func startLog() {
        try? FileManager.default.createDirectory(
            at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: Self.logURL.path, contents: nil)
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Acessório: sem ícone no Dock, sem janela. Vive só na menu bar.
app.setActivationPolicy(.accessory)
app.run()
