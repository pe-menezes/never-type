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
    func transcribe(_ samples: [Float], prompt: String? = nil) -> Result<(text: String, ms: Int), TranscriptionFailure> {
        guard let transcriber else { return .failure(TranscriptionFailure(reason: status)) }
        let started = Date()
        do {
            let text = try transcriber.transcribe(samples, prompt: prompt)
            return .success((text, Int(Date().timeIntervalSince(started) * 1000)))
        } catch {
            return .failure(TranscriptionFailure(reason: "\(error)"))
        }
    }

    func currentStatus() -> String { status }
}

/// Retorno auditivo das ações do ditado.
///
/// A pílula é arrastável e pode estar num canto que você não está olhando — e
/// mesmo olhando, confirmar pelo som é mais rápido que conferir pela cor.
///
/// Os tons são gerados, e não escolhidos entre os do sistema: `Tink` e `Pop` são
/// alertas, desenhados para serem notados. Aqui o som confirma uma ação que a
/// pessoa acabou de fazer de propósito, então precisa ser o contrário disso.
///
/// As notas descem quando algo termina e sobem quando algo começa ou trava —
/// a direção carrega o significado, então dá para saber o que aconteceu sem
/// aprender qual som é qual.
@MainActor
enum Feedback {
    private static let key = "somDasAcoes"

    /// Ligado por padrão, e desligável pelo menu. Som que não se pode desligar é
    /// defeito para quem trabalha em sala compartilhada.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Gerados uma vez. Recriar o WAV a cada ditado seria refazer 3 KB de
    /// aritmética para nada.
    private static let start   = sound(Tone.wav([330], seconds: 0.085))
    private static let stop    = sound(Tone.wav([262], seconds: 0.085))
    private static let latch   = sound(Tone.wav([294, 392], seconds: 0.065))
    private static let discard = sound(Tone.wav([262, 196], seconds: 0.065))

    /// Começou a gravar.
    ///
    /// O tom entra no áudio pelo alto-falante e volta pelo microfone, nos
    /// primeiros ~60 ms da gravação. É um seno curto, não fala, e o Whisper o
    /// ignora — mas é por isso que ele é curto e baixo.
    static func started()   { play(start) }
    static func stopped()   { play(stop) }
    static func latched()   { play(latch) }
    static func discarded() { play(discard) }

    private static func sound(_ data: Data) -> NSSound? {
        let sound = NSSound(data: data)
        sound?.volume = 0.18
        return sound
    }

    private static func play(_ sound: NSSound?) {
        guard isEnabled, let sound else { return }
        // Rebobina: `play()` num som que ainda está tocando não reinicia, e dois
        // ditados seguidos ficariam sem o segundo som.
        sound.stop()
        sound.play()
    }
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
    /// Não é mais uma variável: a última é a primeira do histórico, e ter as
    /// duas coisas criaria duas fontes de verdade para o mesmo texto.
    private var lastTranscript: String? { history.last?.text }

    private let vocabulary = Vocabulary(
        url: logURL.deletingLastPathComponent().appendingPathComponent("vocabulario.json"))
    private lazy var vocabularyWindow = VocabularyWindow(vocabulary: vocabulary)

    private let history = TranscriptHistory(
        url: logURL.deletingLastPathComponent().appendingPathComponent("historico.json"))

    private static var legacyTranscriptURL: URL {
        logURL.deletingLastPathComponent().appendingPathComponent("ultima-transcricao.txt")
    }

    /// O arquivo da versão anterior guardava a última transcrição e agora nunca
    /// mais seria atualizado. Deixá-lo no disco seria abandonar uma cópia do que
    /// a pessoa falou num arquivo que o app não usa e ela não sabe que existe.
    private func removeLegacyTranscriptFile() {
        try? FileManager.default.removeItem(at: Self.legacyTranscriptURL)
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

    /// Consultado ao sistema toda vez, igual ao microfone.
    ///
    /// A pessoa desliga o app em Ajustes do Sistema › Itens de Início de Sessão
    /// sem o app ficar sabendo. Um checkmark guardado em variável passaria a
    /// mentir a partir daí — e o menu se remonta a cada abertura justamente para
    /// nunca mostrar estado velho.
    private var loginItemState: LoginItem.State { LoginItem.current() }

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
        removeLegacyTranscriptFile()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        render(.idle)
        // O menu se remonta ao ser aberto (menuNeedsUpdate), então nunca mostra
        // estado velho.
        menu.delegate = self
        statusItem.menu = menu

        if let saved = HotkeyMonitor.Trigger.named(UserDefaults.standard.string(forKey: Self.triggerKey)) {
            monitor.trigger = saved
        }
        monitor.onEvent = { [weak self] event in self?.handle(event) }
        recorder.onLevel = { [weak self] level in self?.overlay.push(level: level) }
        recorder.onError = { [weak self] message in
            self?.overlay.hide()
            self?.render(.blocked)
            self?.log(message)
        }
        monitor.start()
        // Sempre na tela: um app acessório que morre não muda nada visualmente,
        // então a pílula parada é o único sinal de que ele continua vivo.
        overlay.showIdle()

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
                Feedback.started()
                render(.recording)
                overlay.show()
            } catch {
                render(.blocked)
                log("falha ao iniciar gravação: \(error)")
            }
        case .released:
            Feedback.stopped()
            let url = recorder.stop()
            render(.idle)
            guard url != nil else {
                overlay.hide()
                return
            }
            // A pílula segue na tela dizendo "trabalhando" até o texto sair.
            // Antes ela voltava ao repouso aqui, e o app passava a transcrição
            // inteira sem nenhum sinal do que estava acontecendo.
            overlay.transcribing()
            let samples = recorder.lastSamples
            log("gravado: \(samples.count) amostras (\(String(format: "%.1f", Double(samples.count) / 16_000)) s)")
            Task {
                switch await self.transcription.transcribe(samples, prompt: self.vocabulary.prompt) {
                case .success(let result):
                    // As substituições rodam aqui, sobre o texto pronto: elas são
                    // determinísticas e não passam pelo modelo.
                    let corrected = self.vocabulary.apply(to: result.text)
                    if corrected != result.text {
                        self.log("transcrito em \(result.ms) ms → \(result.text)")
                        self.log("substituições aplicadas → \(corrected)")
                    } else {
                        self.log("transcrito em \(result.ms) ms → \(corrected)")
                    }
                    self.overlay.hide()
                    self.deliver(corrected)
                case .failure(let failure):
                    // Sinal visível: sem isto o ditado sumia em silêncio — o
                    // ícone já voltou ao normal, o app não tem janela, e o
                    // stderr não vai a lugar nenhum quando aberto pelo Finder.
                    self.log("TRANSCRIÇÃO FALHOU: \(failure.reason)")
                    self.overlay.hide()
                    self.render(.blocked)
                }
            }
        case .latched:
            // A gravação já está rolando desde o primeiro toque; aqui só muda
            // quem a mantém viva — a máquina de estados, não a tecla.
            Feedback.latched()
            log("mãos-livres travado. Toque no \(monitor.trigger.label) para transcrever, Esc para descartar.")
        case .cancelled:
            Feedback.discarded()
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
        history.add(text)

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

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Uma linha de menu não comporta um ditado inteiro; o texto completo fica
    /// no tooltip e chega ao pasteboard pelo clique.
    private func preview(of text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 44 ? String(flat.prefix(44)) + "…" : flat
    }

    @objc private func copyFromHistory(_ sender: NSMenuItem) {
        guard history.entries.indices.contains(sender.tag) else { return }
        copy(history.entries[sender.tag].text)
    }

    private static let triggerKey = "trigger"

    @objc private func openVocabulary() {
        vocabularyWindow.show()
    }

    @objc private func chooseTrigger(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let option = HotkeyMonitor.Trigger.named(id) else { return }
        monitor.trigger = option
        UserDefaults.standard.set(id, forKey: Self.triggerKey)
        log("trigger agora é \(option.label)")
    }

    @objc private func toggleSound() {
        Feedback.isEnabled.toggle()
        log("sons: \(Feedback.isEnabled ? "ligados" : "desligados")")
    }

    @objc private func clearHistory() {
        history.clear()
        log("histórico apagado")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc private func copyLastTranscript() {
        guard let lastTranscript else { return }
        copy(lastTranscript)
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
        menu.addItem(disabled("  dois toques travam · toque para encerrar · Esc descarta"))

        let keyItem = NSMenuItem(title: "Tecla", action: nil, keyEquivalent: "")
        let keyMenu = NSMenu()
        for option in HotkeyMonitor.Trigger.all {
            let line = NSMenuItem(title: option.label,
                                  action: #selector(chooseTrigger(_:)), keyEquivalent: "")
            line.target = self
            line.state = option.keyCode == monitor.trigger.keyCode ? .on : .off
            line.representedObject = option.id
            keyMenu.addItem(line)
        }
        keyMenu.addItem(.separator())
        let soundItem = NSMenuItem(title: "Sons",
                                   action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        soundItem.state = Feedback.isEnabled ? .on : .off
        keyMenu.addItem(soundItem)
        keyItem.submenu = keyMenu
        menu.addItem(keyItem)

        let vocab = NSMenuItem(title: "Vocabulário…", action: #selector(openVocabulary), keyEquivalent: "")
        vocab.target = self
        let counts = vocabulary.terms.count + vocabulary.replacements.count
        if counts > 0 {
            vocab.title = "Vocabulário (\(vocabulary.terms.count) termos, \(vocabulary.replacements.count) trocas)…"
        }
        menu.addItem(vocab)

        menu.addItem(.separator())
        menu.addItem(disabled("Microfone: \(micAuthorized ? "ok" : "faltando")"))
        menu.addItem(disabled("Acessibilidade: \(acc ? "ok" : "faltando")"))
        menu.addItem(disabled("Modelo: \(modelStatus)"))
        if let lastTranscript {
            menu.addItem(.separator())
            let copy = NSMenuItem(title: "Copiar última transcrição",
                                  action: #selector(copyLastTranscript), keyEquivalent: "")
            copy.target = self
            copy.toolTip = preview(of: lastTranscript)
            menu.addItem(copy)

            if history.entries.count > 1 {
                let item = NSMenuItem(title: "Histórico (\(history.entries.count))",
                                      action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for (index, entry) in history.entries.enumerated() {
                    let line = NSMenuItem(title: "\(Self.clock.string(from: entry.date))  \(preview(of: entry.text))",
                                          action: #selector(copyFromHistory(_:)), keyEquivalent: "")
                    line.target = self
                    line.tag = index
                    line.toolTip = entry.text
                    submenu.addItem(line)
                }
                submenu.addItem(.separator())
                let clear = NSMenuItem(title: "Limpar histórico",
                                       action: #selector(clearHistory), keyEquivalent: "")
                clear.target = self
                submenu.addItem(clear)
                item.submenu = submenu
                menu.addItem(item)
            }
        }
        if !acc {
            let fix = NSMenuItem(title: "Abrir Ajustes de Acessibilidade…",
                                 action: #selector(openAccessibilitySettings), keyEquivalent: "")
            fix.target = self
            menu.addItem(fix)
        }
        menu.addItem(.separator())
        let loginState = loginItemState
        let login = NSMenuItem(title: "Abrir com o sistema",
                               action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = loginState == .on ? .on : .off
        menu.addItem(login)
        // O item fala a linguagem daqui; o aviso fala a da Apple, que é a que a
        // pessoa vai procurar quando for atrás de onde religar.
        if loginState == .needsApproval {
            menu.addItem(disabled("  desativado em Itens de Início de Sessão"))
            let allow = NSMenuItem(title: "Abrir Itens de Início de Sessão…",
                                   action: #selector(openLoginItemsSettings), keyEquivalent: "")
            allow.target = self
            menu.addItem(allow)
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

    @objc private func toggleLoginItem() {
        let outcome = loginItemState == .on ? LoginItem.disable() : LoginItem.enable()
        switch outcome {
        case .changed(let state):
            log("abrir com o sistema: \(state)")
        case .refused(let reason):
            // Sinal visível, e não só log. O menu já fechou quando isto
            // acontece, o app não tem janela, e o stderr não vai a lugar nenhum
            // quando ele é aberto pelo Finder: sem o ícone, a recusa não
            // chegaria à pessoa.
            log("não consegui mudar 'abrir com o sistema': \(reason)")
            render(.blocked)
            flashIdle()
        }
    }

    @objc private func openLoginItemsSettings() {
        LoginItem.openSettings()
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
