# Auditoria de afirmações — 2026-08-29

> HEAD 0d7efbe. Verificação estática só: leitura de Sources/, Tests/, Package.swift,
> scripts/ e .gitignore. Sem build, sem testes, sem git. Modelo, fixtures e binário
> não existem nesta máquina; tudo que dependeria deles está marcado NV.

## Resumo

| Classe | Total |
|---|---:|
| VERDADEIRA (V) | 336 |
| FALSA (F) | 19 |
| DESATUALIZADA (D) | 8 |
| NÃO VERIFICÁVEL NO CÓDIGO (NV) | 83 |
| **Afirmações** | **446** |

Por arquivo:

| Arquivo | Linhas | V | F | D | NV |
|---|---:|---:|---:|---:|---:|
| README.md | 70 | 48 | 5 | 2 | 15 |
| CLAUDE.md | 30 | 21 | 0 | 1 | 8 |
| docs/INSTALL.md | 39 | 33 | 2 | 0 | 4 |
| docs/armadilhas.md | 28 | 18 | 1 | 0 | 9 |
| docs/escolha-do-modelo.md | 14 | 7 | 0 | 1 | 6 |
| docs/inicializacao-com-o-sistema.md | 10 | 6 | 0 | 0 | 4 |
| fixtures/README.md | 6 | 6 | 0 | 0 | 0 |
| scripts/*.sh (8 arquivos) | 98 | 68 | 6 | 1 | 23 |
| Doc comments em Sources/ + Package.swift + modulemap | 151 | 129 | 5 | 3 | 14 |

Regras de contagem: uma afirmação por linha da tabela; quando a linha carrega duas
classes ("V (mecanismo) / NV (efeito)"), conta a primeira. "V com ressalva" conta
como V e a ressalva fica na evidência. Linha = linha do arquivo auditado.

Além das tabelas: §10 lista 25 comportamentos que existem no código e nenhum doc
público menciona; §11 cruza os números que divergem entre documentos; §12 anota o
que foi visto de passagem em `.vibeflow/` (fora do escopo).

---

## 1. README.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| R1 | Segure uma tecla em qualquer aplicativo, fale, solte, o texto aparece onde o cursor está | 3-4 | V | HotkeyMonitor.swift:222 (monitor global); TextInjector.swift:152-163 (⌘V). Ressalva: ⌘V é postado sem checar se há campo editável (backlog D2) |
| R2 | ~600 ms por ditado, num MacBook Pro M4 Pro | 6 | NV | Medição. Precisa rodar o app e ler `transcrito em N ms` em nevertype.log (main.swift:341-344). Conflita com R47 (~780 ms na L125) |
| R3 | Nenhuma chamada de rede / não há API de rede no código | 6, 15, 158 | V | grep `URLSession\|CFNetwork\|import Network\|NWConnection\|URLRequest` em Sources/, Tests/, Package.swift: vazio |
| R4 | nem framework de rede no binário | 16, 159 | NV | Precisa `otool -L build/NeverType.app/Contents/MacOS/NeverType`. Package.swift:33-36 linka explicitamente só Foundation, Metal, MetalKit, Accelerate |
| R5 | Não existe CI neste repositório | 18 | V | `.github/` inexistente (ls 29/08) |
| R6 | item de DoD, verificado no código e no binário a cada tarefa | 18-20 | NV | Processo humano; nenhum script ou teste automatiza (backlog H3) |
| R7 | macOS 14+ em Apple Silicon | 24 | V | Package.swift:9 `.macOS(.v14)`; install.sh:21 `arm64`; build-app.sh:311 `LSMinimumSystemVersion 14.0` |
| R8 | sem GPU a mesma inferência fica cerca de 11× mais lenta | 24-25 | NV | Medição (armadilhas.md:20: 1635/143 = 11,4×). setup-bench.sh:54 diz "~10x" |
| R9 | Command Line Tools; Xcode completo não é necessário | 26 | V | build-app.sh:273 `swift build`; nenhum .xcodeproj; 7/7 arquivos de teste importam `Testing`, 0 `XCTest` |
| R10 | cmake, só para compilar | 27 | V | build-app.sh:190; linkagem estática Package.swift:28-37 |
| R11 | O .app é autocontido; quem for apenas usar não precisa de nada instalado além dele | 29-30 | F | O modelo (547 MB) fica fora do app, em `~/Library/Application Support/NeverType/models/` (Transcriber.swift:8-13), e sem ele o app falha com `modelMissing` (Transcriber.swift:80-82). O app não baixa nada. "Autocontido" vale só para o whisper.cpp |
| R12 | `install.sh` compila, instala em /Applications, cuida do modelo e abre o app | 35-38 | V | install.sh:32-35 (compila SÓ se `build/NeverType.app` não existir — build/ velho é instalado sem aviso), :56-58, :71-89 (modelo: promove de models/ ou só imprime instrução, não baixa), :114 |
| R13 | o modelo tem 547 MB | 39 | NV | Precisa do arquivo. Consistente em 9 lugares. O piso que o app aceita é 50 MB (Transcriber.swift:25) |
| R14 | Na primeira execução o macOS pede Microfone e Acessibilidade | 41-43 | V | main.swift:484-487 (`requestAccess`); :496 (`AXIsProcessTrustedWithOptions` com prompt) |
| R15 | sem Acessibilidade fica mudo, sem erro nenhum, parecendo quebrado | 42-43 | F | Mudo à tecla, sim; "sem erro nenhum", não: ícone vira `mic.slash` (main.swift:494), log "Acessibilidade não concedida" (:495), menu "Acessibilidade: faltando" (:536) e item "Abrir Ajustes de Acessibilidade…" (:569) |
| R16 | `bash scripts/verificar-instalacao.sh` | 48 | V | Arquivo existe, 124 linhas |
| R17 | Não há binário pré-compilado; é isso que dispensa o Gatekeeper | 53-54 | NV | Sem release no repo (V). Comportamento do Gatekeeper com build local é do macOS |
| R18 | docs/INSTALL.md tem os três momentos que exigem você clicando | 55-58 | F | INSTALL.md tem 4 marcadores "PARE E PEÇA": L51, L123, L128, L157 |
| R19 | Segure ⌘ direito | 62 | V | Padrão: HotkeyMonitor.swift:192 `trigger: Trigger = .rightCommand` |
| R20 | Apertar qualquer tecla comum durante o hold cancela e descarta o áudio | 63 | V | HotkeyMonitor.swift:90-92, :253-255; main.swift:362-367 → AudioRecorder.swift:405-409 → :208-211 (apaga arquivo e amostras) |
| R21 | A tecla sai do menu: ⌘, ⌥ ou ⌃ do lado direito, e só esses | 63-66 | V | HotkeyMonitor.swift:140-150; main.swift:509-516 |
| R22 | Dois toques travam; um toque encerra; Esc descarta; toque < 250 ms; segundo em 300 ms | 68-70 | V | HotkeyMonitor.swift:37 (0.25), :39 (0.30), :95-97, :110-116 |
| R23 | Travado, teclar não cancela | 70-73 | V | HotkeyMonitor.swift:124-125; teste AudioRecorderTests.swift:378-384 |
| R24 | Enquanto grava, o ícone da menu bar fica vermelho | 75 | V | main.swift:293 `.systemRed`; forma vira `mic.fill` (:279) |
| R25 | aparece um indicador flutuante na base da tela | 75-77 | D | A pílula está SEMPRE na tela desde o lançamento (main.swift:236 `showIdle`; RecordingOverlay.swift:211-213), `hide()` não esconde (:245-250). Posição padrão é o canto inferior direito (:308), mas é arrastável, gruda em qualquer borda (:319-343) e a posição fica em UserDefaults `overlayOrigin` (:220). Mudou com U1/U2 (28-29/08) |
| R26 | sobrevive a aplicativos em tela cheia | 76-77 | V | RecordingOverlay.swift:279-280 (`.screenSaver`, `.fullScreenAuxiliary`) |
| R27 | tons: o que encerra soa mais grave que o que começa, e o que trava sobe | 77-79 | V | main.swift:97-100: começo 330 Hz, fim 262 Hz, trava 294→392, descarte 262→196 |
| R28 | A área de transferência é devolvida, inclusive imagem, arquivo e HTML | 81-83 | V | TextInjector.swift:27-47 (todos os tipos), :130-143; teste TextInjectorTests.swift:56-73 |
| R29 | Se a inserção não puder acontecer, o texto fica em "Copiar última transcrição" e é gravado em disco | 83-84 | V | main.swift:377 (`history.add` antes de inserir), :539-545; TranscriptHistory.swift:73-80 |
| R30 | Tecla — ⌘, ⌥ ou ⌃ direito, com marca na atual; guardada e restaurada | 88-89 | V | main.swift:507-516 (marca :513), :441 (`UserDefaults` chave `trigger`), :223-225 |
| R31 | Sons — no mesmo submenu, ligados por padrão | 90 | V | main.swift:517-522; :90-93 (`?? true`) |
| R32 | Vocabulário… — duas listas, com as contagens no próprio item | 92-93 | V | main.swift:526-531. Ressalva: contagens só aparecem quando a soma > 0 |
| R33 | Histórico — últimas 30, mais recente primeiro, com a hora; submenu a partir da segunda; clicar copia; texto no tooltip; limpar por ali | 95-97 | V | TranscriptHistory.swift:31, :50; main.swift:547 (`> 1`), :552 (HH:mm), :417-420, :556, :560-563 |
| R34 | Fica em texto claro em `~/Library/Application Support/NeverType/` | 97-99 | V | main.swift:161-162 (`historico.json`); TranscriptHistory.swift:76-79 (JSON sem cifra) |
| R35 | Abrir com o sistema — só da cópia instalada (/Applications ou ~/Applications); de outro lugar recusa e manda rodar o install.sh | 100-101 | V | LoginItem.swift:62-67, :100-105 |
| R36 | Desligado nos Ajustes, o menu diz isso e oferece o atalho | 102 | V | main.swift:583-589; LoginItem.swift:137-139 |
| R37 | Modelo: Whisper large-v3-turbo quantizado (q5_0), 547 MB | 108 | V | Nome: Transcriber.swift:6; setup-bench.sh:23. Tamanho: NV |
| R38 | Motor: whisper.cpp compilado estático, backend Metal | 109 | V | build-app.sh:222-228 (`BUILD_SHARED_LIBS=OFF`, `GGML_METAL=ON`); Package.swift:28-37 |
| R39 | Licença do modelo MIT — código e pesos | 110 | NV | Fato externo (OpenAI) |
| R40 | Captura: AVAudioEngine, convertido para 16 kHz mono | 111 | V | AudioRecorder.swift:317, :5-6 |
| R41 | Tecla global: NSEvent em modo escuta, sem interceptar | 112 | V | HotkeyMonitor.swift:222 (`addGlobalMonitorForEvents`), :231 |
| R42 | Inserção: área de transferência + ⌘V sintético | 113 | V | TextInjector.swift:120-124, :152-163 |
| R43 | Modelo carregado uma vez no lançamento e mantido quente | 115-116 | V | main.swift:243-244, :31-50; Transcriber.swift:148-156 |
| R44 | A latência não cresce com o tamanho da frase; janelas de 30 s | 118-120 | NV | Interno do whisper.cpp. A medição de backlog.md:108-121 (5 ditados) sustenta |
| R45 | link `[Limitações](#limitações)` | 120 | F | Heading é "## Limitações conhecidas" (L122) → âncora `#limitações-conhecidas`; L94 usa a certa (backlog H4) |
| R46 | Ditado acima de 30 segundos passa do alvo de latência | 124 | NV | Teto 1500 ms (escolha-do-modelo.md:15; bench.sh:19). A medição no app de 28/08 deu 1299 ms para 31 s (backlog.md:114) — dentro do teto. O "passa" vem da bancada (820 × 2 = 1640) |
| R47 | Abaixo disso todo ditado custa ~780 ms | 125 | D | 782 ms é o whisper-cli (escolha-do-modelo.md:29). No app: 599–609 ms (escolha-do-modelo.md:36) e 612–698 ms (backlog.md:110-113). Contradiz a L6 do mesmo README |
| R48 | Não há aviso nem limite | 125-126 | V | Nenhuma verificação de duração em AudioRecorder.swift nem main.swift (grep `seconds\|duration\|> 30`: só os tons e o `flashIdle`) |
| R49 | o macOS coloca fones Bluetooth em modo HFP a 8 kHz | 128-129 | NV | Comportamento do SO |
| R50 | A conversão funciona (há teste) | 130 | V | AudioRecorderTests.swift:69-77 |
| R51 | termos viram `initial_prompt` (probabilístico); só as substituições são determinísticas | 132-137 | V | Vocabulary.swift:60-63, :71-82; Transcriber.swift:186-189; main.swift:335-339 |
| R52 | secure input é flag global; enquanto ligada o app não cola, deixa o texto na área de transferência e avisa | 139-144 | V | TextInjector.swift:100-110; main.swift:382-387 (log + `mic.slash` por 2 s, :397-402). O "aviso" é só ícone e log, e a mensagem diz "campo de senha em foco" (:385) — o falso positivo do D3 |
| R53 | O texto é marcado com `org.nspasteboard.ConcealedType` | 146-147 | F | Verdade na inserção (TextInjector.swift:60, :107, :123). "Copiar última transcrição" e os itens do histórico (main.swift:455-458) escrevem SEM a marca e sem devolução — esses vão para o histórico de gestores |
| R54 | que Raycast e Maccy respeitam | 147 | NV | Fato externo |
| R55 | Colar substitui a seleção | 150 | V | Consequência do ⌘V (TextInjector.swift:158-161) |
| R56 | Mover o app quebra a permissão; caminho fixo + assinatura estável fazem a Acessibilidade sobreviver | 152-154 | NV | Tensão interna: build-app.sh:7-12 diz que o TCC ancora no certificado (requisito designado), não no caminho; install.sh:2-6 repete a versão "caminho fixo". Só movendo o app instalado se sabe |
| R57 | hardened runtime liga validação de bibliotecas; por isso o whisper.cpp entra estático | 162-166 | V | build-app.sh:338-340 (`--options runtime`); Package.swift:16-27 |
| R58 | certificado local estável; o macOS amarra Mic e Acessibilidade a ele; quem executa código pode se assinar como NeverType | 168-172 | V | Mecanismo: build-app.sh:2-12, :62-64, :338. Comportamento do TCC: NV |
| R59 | a senha do keychain é derivada do identificador da máquina, nunca versionada | 178 | V | build-app.sh:37-43 (`IOPlatformUUID` → sha256) |
| R60 | a chave privada é liberada só ao codesign | 179 | V | build-app.sh:112 (`-T /usr/bin/codesign`). Ressalva: :118 libera também as partições `apple-tool:` e `apple:` |
| R61 | o keychain fica em modo 600 e é travado ao fim de cada build | 180 | V | build-app.sh:121, :164-165, :162 (`trap … EXIT`) |
| R62 | Para distribuição além de uso pessoal, o certo é um Developer ID | 182 | NV | Recomendação |
| R63 | `~/Library/Keychains/nevertype-signing.keychain-db`; apagá-lo faz o próximo build gerar outro certificado | 184-186 | V | build-app.sh:22, :152-155 (`identity_present \|\| create_identity`), :104-105 |
| R64 | `build-app.sh` — primeira vez compila o whisper.cpp em vendor/ | 191 | V | build-app.sh:178, :259-267 |
| R65 | Sem vendor/ o swift build falha com `could not build Objective-C module 'CWhisper'` | 195-196 | NV | O módulo aponta para vendor/ (module.modulemap:9-10); a mensagem exata só aparece rodando `swift build` sem vendor/ |
| R66 | 81 testes em swift-testing | 198 | V | 81 `@Test(`: AudioRecorder 31, TextInjector 9, LoginItem 9, Tone 6, Vocabulary 12, Transcriber 7, TranscriptHistory 7. 2 são condicionais a modelo + fixture (TranscriberTests.swift:111) |
| R67 | o XCTest só existe com o Xcode completo | 198-199 | NV | Fato do toolchain |
| R68 | `Sources/NeverTypeCore/` — conversão de áudio, tecla, transcrição, inserção | 207 | V | Incompleta: também Vocabulary, TranscriptHistory, Tone, LoginItem (4 de 8 arquivos) |
| R69 | tabela de scripts: setup-bench, bench, build-app, install | 209-212 | V | Incompleta: faltam atualizar.sh, verificar-instalacao.sh, fetch-model.sh, record-fixture.sh; faltam docs/INSTALL.md e docs/inicializacao-com-o-sistema.md |
| R70 | MIT; depende de whisper.cpp (MIT) e do modelo (MIT) | 218-219 | V | LICENSE:1 "MIT License". Licenças de terceiros: NV |

## 2. CLAUDE.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| C1 | Segurar ⌘ direito grava, soltar transcreve | 3-4 | V | Padrão (HotkeyMonitor.swift:192). Incompleta: três teclas (:150) e trava por duplo toque (:95-97) — backlog H6 |
| C2 | Nenhuma chamada de rede em tempo de uso | 4-5 | V | grep vazio em Sources/, Tests/, Package.swift |
| C3 | há check de DoD verificando isso no código e no binário | 5-6 | NV | Processo humano; sem script ou teste (H3). README:18 já diz "manual" |
| C4 | App de menu bar acessório (sem Dock, sem janela) | 8 | D | Tem janela desde o vocabulário: VocabularyWindow.swift:4-5 ("É a primeira janela do app"), :46-53 (`NSWindow`); mais o `NSPanel` da pílula (RecordingOverlay.swift:264-270). "Sem Dock" continua V (main.swift:681; build-app.sh:312) |
| C5 | macOS 14+, Apple Silicon | 8 | V | Package.swift:9; install.sh:21 |
| C6 | Swift 6 com concorrência estrita, SwiftPM, sem Xcode | 9 | V | Package.swift:1 (`swift-tools-version: 6.0`); build-app.sh:4-5, :273 |
| C7 | leia index.md, conventions.md, os oito pattern docs, docs/armadilhas.md | 13-16 | V | 8 arquivos em .vibeflow/patterns/; os outros existem |
| C8 | um log de execução em CPU contém 37 linhas com "metal" | 24-26 | NV | Medição (armadilhas.md:15-17) |
| C9 | `head -c 4` de um modelo ggml é `lmgg` | 27-28 | V | Transcriber.swift:47 (`6c6d6767`); setup-bench.sh:94-99 |
| C10 | `MainActor.assumeIsolated` só onde a API documenta main thread e a ordem importa | 29-31 | V | 4 usos, todos comentados: HotkeyMonitor.swift:215-223, :270-277; RecordingOverlay.swift:76-79; TextInjector.swift:131 (`asyncAfter` na main) |
| C11 | isso derrubou o app duas vezes | 30-31 | NV | Histórico; main.swift:473-483 registra |
| C12 | Estado do sistema é consultado, nunca guardado | 32 | V | main.swift:182-184, :192; HotkeyMonitor.swift:198-200; LoginItem.swift:84-86 |
| C13 | swift-testing, nunca XCTest | 33 | V | 7/7 arquivos com `import Testing`; 0 `XCTest` |
| C14 | Todo caminho de falha precisa ser exercitável; em quatro auditorias… | 34-36 | NV | Regra e histórico |
| C15 | `build-app.sh` compila o whisper.cpp estático em vendor/ | 43 | V | build-app.sh:189-252 |
| C16 | sem vendor/ o build falha com `could not build Objective-C module 'CWhisper'` | 46-48 | NV | Idem R65 |
| C17 | clona num commit fixo, confere, compila e guarda | 49-50 | V | build-app.sh:187, :196, :202-209, :250 |
| C18 | Leva alguns minutos na primeira vez, ~1 s nas seguintes | 50 | NV | Tempo. Nas seguintes roda `shasum -c` de 6 `.a` (build-app.sh:254-257) |
| C19 | `swift build && swift test` — 81 testes | 54 | V | 81 `@Test(`; 79 rodam sem modelo e fixture |
| C20 | `install.sh` instala em /Applications | 55 | V | install.sh:11, :56-58 |
| C21 | `bench.sh` mede latência e qualidade por modelo | 56 | V | bench.sh:98-191 |
| C22 | Fora do controle de versão: models/ (1,2 GB), vendor/, fixtures/, bench-out/, .cache/, build/ | 59-60 | V | .gitignore:3-24 (os seis). 1,2 GB: NV |
| C23 | Nunca apague o keychain — apagá-lo revoga a Acessibilidade | 62-64 | V | Mecanismo: build-app.sh:22, :155 (sem o arquivo → `create_identity` → certificado novo). Revogação pelo TCC: NV |
| C24 | Código e APIs em inglês; comentários, erros, interface e docs em português | 68-69 | V | Hoje: 754 linhas de comentário PT em Sources/, ~40 strings de UI PT (inventário i18n). Muda na etapa 2 |
| C25 | ~600 ms por ditado | 73 | NV | Idem R2 |
| C26 | 81 testes | 73 | V | Idem R66 |
| C27 | Nunca foi instalado por ninguém além do autor | 73-74 | NV | Fato externo |
| C28 | cada instalação ainda compila na própria máquina | 76-77 | V | Sem release; install.sh:32-35 |
| C29 | Abrir no login, histórico e vocabulário implementados (LoginItem.swift, TranscriptHistory.swift, Vocabulary.swift), com teste | 77-80 | V | Os 3 arquivos em Sources/NeverTypeCore/; LoginItemTests 9, TranscriptHistoryTests 7, VocabularyTests 12 |
| C30 | certificado local: quem executa código na máquina pode usá-lo; alternativa revoga a cada build | 84-88 | V | build-app.sh:33-36, :108-111, :7-12 |

## 3. docs/INSTALL.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| I1 | compilado na máquina de quem instala — não há binário pré-compilado | 7-10 | V | Sem release no repo; build-app.sh |
| I2 | app compilado localmente não entra em quarentena, então o Gatekeeper não aparece | 9-10 | NV | Comportamento do macOS |
| I3 | Três coisas exigem a pessoa, marcadas com PARE E PEÇA | 18-20 | F | 4 marcadores: L51, L123, L128, L157 |
| I4 | `brew install cmake` (pode) | 26 | V | build-app.sh:190 |
| I5 | Apagar `~/Library/Keychains/nevertype-signing.keychain-db` (parar) | 27 | V | build-app.sh:22 |
| I6 | Escrever fora do repositório e de `~/Library/Application Support/NeverType/` (parar) | 28 | V | É onde o app escreve: main.swift:8-9, :158, :162, :662; Transcriber.swift:10. Fora dessa fronteira o app escreve em UserDefaults (`com.nevertype.app`, main.swift:86, :422; RecordingOverlay.swift:220) e o build em `~/Library/Keychains/` |
| I7 | Instalar em /Applications sem permissão de escrita (parar) | 29 | V | install.sh:26-28 |
| I8 | Apagar um modelo inválido e rebaixar (pode) | 30 | V | verificar-instalacao.sh:92, :96 mandam `rm` |
| I9 | `security list-keychains -s` substitui a lista inteira; o build-app.sh tem guarda-corpo | 32-35 | V | build-app.sh:127-148 |
| I10 | apagar o keychain revoga a Acessibilidade | 37-38 | V | Mecanismo: build-app.sh:104-105, :155. TCC: NV |
| I11 | Darwin, arm64, macOS 14 ou maior | 43-45 | V | install.sh:20-21; Package.swift:9; build-app.sh:311. Nenhum script confere a versão do macOS — só o `LSMinimumSystemVersion` do plist impede abrir |
| I12 | Sem Metal ~11× mais lenta, e o projeto recusa de propósito | 48-49 | V | Recusa: install.sh:21, verificar-instalacao.sh:41, setup-bench.sh:38. build-app.sh:50 só recusa não-Darwin — em Intel compila e o install recusa depois. 11×: NV |
| I13 | `xcode-select -p` falha se não instaladas | 54 | V | Comando padrão |
| I14 | Xcode completo não é necessário | 63 | V | Idem R9 |
| I15 | cmake só para compilar; não é dependência de execução | 69, 72 | V | build-app.sh:190; Package.swift:28-37 |
| I16 | `git clone <url-do-repositório> nevertype` | 77 | NV | Placeholder. O repositório é privado (github.com/pe-menezes/never-type): um agente de fora não clona sem acesso |
| I17 | build-app.sh clona num commit fixo, confere, compila estático e assina | 82-83 | V | build-app.sh:187-210, :222-228, :338-341 |
| I18 | install.sh recusa cedo (não-Darwin, não-arm64, /Applications sem escrita), instala, verifica assinatura e confere o modelo | 85-86 | V | install.sh:20-26, :56-58, :71-89 |
| I19 | `~/Applications/` é caminho alternativo | 88-90 | V | install.sh:26-28 sugere; LoginItem.swift:66 aceita. Lacuna: verificar-instalacao.sh:14, atualizar.sh:14 e install.sh:11 só conhecem `/Applications` — quem instalar em ~/Applications recebe "não existe /Applications/NeverType.app" (verificar-instalacao.sh:64) |
| I20 | São 547 MB e ele não vem no app; o install.sh avisa se faltar | 94 | V | install.sh:80-88 |
| I21 | `setup-bench.sh` baixa do CDN da OpenAI e converte, ~10 min | 97 | V | CDN: setup-bench.sh:18. Incompleta: baixa e converte TRÊS checkpoints (:22-26 — turbo, medium, small), exige Homebrew (:39), instala `whisper-cpp` via brew (:46) e cria venv com torch (:152-157). Nada disso está nos Requisitos do README (L22-30) nem neste doc. 10 min: NV |
| I22 | `fetch-model.sh` promove para o lugar definitivo | 98 | V | fetch-model.sh:36-41 |
| I23 | página HTML de erro salva com nome de modelo; a validação confere o magic em hexadecimal | 103-105 | V | fetch-model.sh:14, :20-23; verificar-instalacao.sh:21, :87-92 |
| I24 | o arquivo precisa entrar pelo repositório, nunca direto no destino | 107-108 | V | Verdade como regra do doc. Contradita por install.sh:86-87, que manda copiar DIRETO para `$MODEL_DIR/` "e pule as duas etapas acima" |
| I25 | fetch-model.sh valida magic e tamanho antes de promover, e apaga a cópia se não ficar válida | 115-117 | V | fetch-model.sh:20-23, :40. Ressalva: o piso é 50 MB (:22), que armadilhas.md:58-59 chama de insuficiente; install.sh:75 e verificar-instalacao.sh:24 usam 400 |
| I26 | Duas permissões, e o app pede as duas ao abrir | 121 | V | main.swift:238-239 |
| I27 | Sem Acessibilidade o app abre, desenha o ícone e não reage à tecla — sem erro, sem alerta, sem nada no log que a pessoa veja | 130-132 | F | Idem R15: ícone `mic.slash`, menu "Acessibilidade: faltando" + item de atalho, linha no log, e o prompt do sistema (main.swift:496) |
| I28 | Ajustes › Privacidade e Segurança › Acessibilidade; "+" e `/Applications/NeverType.app` | 134-136 | NV | Interface do macOS. Caminho do bundle: V (install.sh:11) |
| I29 | Depois de ligar, encerre pelo menu da bandeja e abra de novo | 141 | V | Item existe (main.swift:591). Necessidade do reinício: NV — os monitores são instalados uma vez em `start()` (HotkeyMonitor.swift:211-235, main.swift:233) |
| I30 | verificar-instalacao.sh confere app, assinatura, processo e modelo por bytes; sai ≠ 0 e lista tudo | 151-152 | V | verificar-instalacao.sh:52-100, :34-38, :105-107 |
| I31 | Ele não verifica permissão | 154 | V | verificar-instalacao.sh:8-10, :111 |
| I32 | a busca do Spotlight não | 159-160 | NV | Sem justificativa em código ou doc |
| I33 | Segure o ⌘ da direita | 162 | V | Padrão, idem R19 |
| I34 | `bash scripts/atualizar.sh` | 174 | V | Existe, 90 linhas |
| I35 | compara instalado (carimbado no bundle), local e remoto; igual não faz nada; diferença: traz, compila, instala, verifica | 177-180 | V | atualizar.sh:48-68, :70-85; build-app.sh:288, :310 |
| I36 | Ele para em dois casos: alterações locais; pull não fast-forward | 182-188 | V | atualizar.sh:31-36, :72-75. Incompleta: para também sem git (:22-25), sem remoto (:41-43), fetch falho (:46), branch sem upstream (:50-52) |
| I37 | permissões sobrevivem à atualização; keychain nunca apagado | 190-193 | V | Mecanismo: build-app.sh:2-12, :22 |
| I38 | A versão instalada aparece no menu, em "Versão" | 197 | V | main.swift:538, :429-431 |
| I39 | Como usar: ⌘ direito; dois toques; Esc; tecla comum cancela; menu tem histórico, tecla e vocabulário | 201-204 | V | HotkeyMonitor.swift:90-125; main.swift:507, :526, :548 |

## 4. docs/armadilhas.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| A1 | log de `whisper-cli -ng` contém 37 linhas com "metal" | 15-17 | NV | Medição |
| A2 | encode 1635 ms em CPU contra 143 ms em Metal | 19-21 | NV | Medição |
| A3 | `metal_is_active` exige o positivo e rejeita o negativo | 26-31 | V | bench.sh:33-37; setup-bench.sh:69-73 (idênticas) |
| A4 | dentro do processo enumera `ggml_backend_dev_count()` e lê `ggml_backend_dev_name()` | 34-35 | V | Transcriber.swift:112-114 |
| A5 | magic `0x67676d6c` little-endian → `lmgg`; comparar como texto reprovava todo modelo | 41-46 | V | Transcriber.swift:47; fetch-model.sh:21; setup-bench.sh:106; verificar-instalacao.sh:87; teste TranscriberTests.swift:21-26 |
| A6 | modelo truncado aceito como "modelo vazio"; `std::out_of_range`; exit 134 | 50-56 | NV | Reprodução. A guarda existe (Transcriber.swift:15-25, :83-85; teste TranscriberTests.swift:45-58) |
| A7 | Regra: magic E piso proporcional ao artefato real; "um piso de 50 MB para um modelo de 547 MB aprova download truncado" | 58-59 | F | Como descrição do código: o piso é 50 MB em Transcriber.swift:25 (`minimumBytes`, o que o app aceita ao abrir), fetch-model.sh:22 e setup-bench.sh:103. Só install.sh:75 e verificar-instalacao.sh:24 usam 400 MB. A regra vale em 2 de 5 lugares |
| A8 | callback do TCC em fila de background; `Task { @MainActor in }` não resolve; API assíncrona | 69-84 | V | main.swift:473-487 |
| A9 | o caminho só roda quando a permissão está indefinida | 86-87 | V | main.swift:469 (`== .notDetermined`) |
| A10 | tap em thread de tempo real; fila serial dona do estado; `queue.sync` como barreira | 91-97 | V | AudioRecorder.swift:277-284, :330-359, :396-400 |
| A11 | `NSRunningApplication` falhou 3 de 3; `flock` resolve | 101-107 | NV | 3 de 3: medição. flock: V (main.swift:644-658) |
| A12 | 982 quadros retidos em 1 s a 48 kHz (61 ms) | 115-118 | NV | Medição. Dreno: AudioRecorder.swift:102-107; teste :81-89 |
| A13 | 3744 quadros perdidos convertendo 8 kHz | 124-127 | NV | Medição. `pump`: AudioRecorder.swift:110-126; teste :69-77 |
| A14 | motor parado segura o microfone; nasce e morre por uso; `defer` no erro | 131-139 | V | AudioRecorder.swift:270-275, :323-324, :388-389 |
| A15 | `NSStatusItem` antes de `setActivationPolicy` é descartado | 145-150 | V | O código segue a regra: main.swift:129-135, :216, :681 |
| A16 | imagem template; `contentTintColor` só tinge template | 152-159 | V | main.swift:284-293 |
| A17 | `NSPanel` `level = .screenSaver` + `.fullScreenAuxiliary` | 161-165 | V | RecordingOverlay.swift:279-280 |
| A18 | `IsSecureEventInputEnabled()` é flag global da sessão | 167-172 | V | TextInjector.swift:100-103 |
| A19 | `find-identity -v -p codesigning` filtra por confiança; usar sem filtros | 174-181 | V | build-app.sh:55-64 |
| A20 | hardened runtime incompatível com dylib de terceiro; `different Team IDs` | 183-195 | V | Decisão: build-app.sh:168-176, :338-340; Package.swift:16-27. Mensagem: NV |
| A21 | três guardas (geração, retrato herdado, `changeCount`) + ConcealedType | 201-219 | V | TextInjector.swift:62-84, :112-118, :129-143, :60 |
| A22 | `set -e` + `pipefail` tornam fallbacks inalcançáveis; `{ grep … \|\| true; }` | 225-233 | V | bench.sh:132-138 |
| A23 | `trap … RETURN` não dispara em `exit`; some `EXIT` | 235-239 | V | build-app.sh:70-74 |
| A24 | `osascript` pede Automação; use `pkill` | 241-245 | V | install.sh:39-49 |
| A25 | `sleep` fixo não é espera; espere a condição | 247-251 | V | install.sh:50-54 |
| A26 | 5087 ms de parede contra 976 ms; aquecer o cache e usar o cronômetro interno | 257-266 | NV | Números: medição. Bancada: V (bench.sh:81-91, :140-145) |
| A27 | latência declarada com base em uma amostra | 268-273 | NV | Histórico |
| A28 | em quatro auditorias, nenhum caminho de falha não exercitado estava correto | 289-291 | NV | Histórico |

## 5. docs/escolha-do-modelo.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| E1 | medidos em gravações reais de fala em português com termos em inglês | 3-4 | NV | Fixtures não versionados |
| E2 | Teto: 1500 ms | 15 | V | bench.sh:19 |
| E3 | janelas de 30 segundos; custo por janela | 20-21 | NV | Interno do whisper. É o modelo da bancada (bench.sh:148-152) |
| E4 | descontam o carregamento; cronômetro interno do processo | 23-25 | V | bench.sh:140-146 |
| E5 | tabela 782/820, 737/856, 290/346 ms | 27-31 | NV | bench-out/ não versionado |
| E6 | no app real um ditado curto mediu 599–609 ms | 36 | NV | Medição |
| E7 | tabela de qualidade por tipo de erro | 43-50 | NV | Transcrições em bench-out/ |
| E8 | 547 MB, quantizado localmente a partir do checkpoint da OpenAI | 54 | V | Processo: setup-bench.sh:23, :205-234 |
| E9 | small é 2,7× mais rápido | 59 | V | Aritmética sobre E5: 782/290 = 2,7 |
| E10 | turbo (820 ms/janela) passa de 1500 ms em duas janelas; só small aguenta duas | 71-73 | V | Aritmética: 1640, 1712, 692. Contradita pela medição no app: 1299 ms para 31 s (backlog.md:114) |
| E11 | vocabulário customizado (prompt inicial), que este projeto ainda não tem | 81-84 | D | Existe: Vocabulary.swift:56-63 (`prompt`) + Transcriber.swift:186-189 (`initial_prompt`). Commit 43d968f (backlog A3). README:132-137 já descreve |
| E12 | setup-bench.sh, record-fixture.sh 01-normal, bench.sh | 89-91 | V | Os três existem; record-fixture.sh:18 aceita `<nome>` |
| E13 | A bancada aborta se a inferência cair para CPU | 94-95 | V | bench.sh:123-130 |
| E14 | ~11× maior | 94 | NV | Idem R8 |

## 6. docs/inicializacao-com-o-sistema.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| N1 | Medido em 2026-08-28, macOS 26.2, modelo de 547 MB | 3-4 | NV | Medição |
| N2 | O app não muda nada no lançamento por causa desta opção: carrega e aquece como sempre | 6-8 | V | main.swift:243-244 (incondicional); LoginItem não toca o lançamento |
| N3 | Cronômetro de fora do processo: de `open` até a linha aparecer no log | 12-13 | V | Método coerente: main.swift:247 (`log("modelo: …")`) |
| N4 | tabela 784/8303/6874, 142/951/178, 162/965/172; aquecimento 614–622 ms | 15-22 | NV | Medição |
| N5 | 8303 ms é piso, não teto | 31-33 | NV | Raciocínio sobre medição |
| N6 | nos primeiros ~8 s, segurar ⌘ direito grava, mas a transcrição espera o modelo | 37-39 | V | Por construção: `TranscriptionService` é `actor` (main.swift:20) e `prepare()` não tem `await` (:32-50), então `transcribe()` (:335) fica na fila do ator até a carga terminar. Só falha se a carga falhar (:59) |
| N7 | A spec decidiu não carregar o modelo sob demanda | 41-45 | V | specs/abrir-com-o-sistema.md:91-93 |
| N8 | abra o menu e leia `Modelo: Metal · carga N ms · aquecimento N ms` | 51-53 | V | main.swift:41-43, :537 |
| N9 | build-app.sh; `pkill -x NeverType`; `rm nevertype.log`; `open build/NeverType.app`; linha "modelo:" | 59-63 | V | main.swift:660-662, :247. O `pkill` é necessário: a segunda instância cede à primeira (:205-211) |
| N10 | sem reiniciar, page cache quente dá 951 ms | 66-67 | NV | Medição |

## 7. fixtures/README.md

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| X1 | Nada aqui vai pro git além deste README | 4 | V | .gitignore:3-4 |
| X2 | `record-fixture.sh <nome> [segundos] [dispositivo]` | 9-11 | V | record-fixture.sh:18-20 |
| X3 | Sem argumento lista os dispositivos; padrão `[0]`; índice como terceiro argumento | 14-15 | V | record-fixture.sh:20, :27-38 |
| X4 | grava em 16 kHz mono PCM 16-bit; QuickTime sai 44,1 kHz estéreo e a bancada rejeita | 17-18 | V | record-fixture.sh:73; bench.sh:62-67 |
| X5 | pelo menos três áudios, curto e longo (janela de 30 s) | 22-25 | V | bench.sh:54-58 avisa com menos de 3 |
| X6 | o diretório está no .gitignore, e bench-out/ também | 53 | V | .gitignore:3, :10 |

Ausente neste README: `record-fixture.sh` exige `ffmpeg` (record-fixture.sh:25) — ver §10.

## 8. scripts/*.sh — cabeçalhos e mensagens ao usuário

### scripts/atualizar.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S1 | recusa em dois casos: alterações locais não commitadas, e repositório sem git | 2-6 | V | :22-25, :31-36. Recusa também sem remoto (:41-43) e sem upstream (:50-52) |
| S2 | permissões sobrevivem porque o certificado é estável; o keychain nunca deve ser apagado | 8-10 | V | Mecanismo: build-app.sh:2-12, :22 |
| S3 | `APP="/Applications/NeverType.app"` | 14 | V | Lacuna: não cobre `~/Applications` (I19) |
| S4 | "Se você baixou um tarball, clone e rode build-app.sh && install.sh" | 23-25 | V | Os dois scripts existem |
| S5 | `NeverTypeCommit` lido do Info.plist | 56, 88 | V | build-app.sh:310; main.swift:430 |
| S6 | o ditado só está provado depois que você ditar | 89-90 | V | Coerente com verificar-instalacao.sh:111-119 |

### scripts/bench.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S7 | imprime a tabela que sustenta a decisão em `docs/decisao-modelo.md` | 2-4 | F | Arquivo não existe; é `docs/escolha-do-modelo.md` |
| S8 | Teto declarado no PRD: 1500 ms | 17-19 | V | Valor: escolha-do-modelo.md:15. O PRD do modelo não está no repo (só 2 PRDs em .vibeflow/prds/) |
| S9 | 37 linhas com "metal"; 1635 vs 143 ms | 27-32 | NV | Idem A1-A2 |
| S10 | "whisper-cli não encontrado. Rode scripts/setup-bench.sh" | 39 | V | setup-bench.sh:41-49 instala |
| S11 | "A spec pede ao menos 3 [fixtures]" | 50-57 | NV | Spec não está no repo. fixtures/README.md:22 pede o mesmo |
| S12 | "Regrave com scripts/record-fixture.sh — o QuickTime grava em 44,1 kHz" | 64-65 | V | record-fixture.sh:73 |
| S13 | "DoD 4" | 123 | NV | Referência a spec ausente do repo |
| S14 | "Verifique: brew reinstall ggml whisper-cpp" | 127-129 | NV | Ação externa |
| S15 | janelas de 30 s; 5 s custa o mesmo que 25 s | 148-150 | NV | Idem E3 |
| S16 | "teto do PRD" | 196 | V | Idem S8 |
| S17 | "Agora preencha: docs/decisao-modelo.md" | 230 | F | Idem S7 |

### scripts/build-app.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S18 | Sem Xcode; o executável sai do SwiftPM e o bundle é montado aqui | 2-5 | V | :273, :290-317 |
| S19 | TCC guarda o requisito designado; ad-hoc muda a cada build; "verificado: dois binários com cdhash diferente compartilham certificate leaf" | 7-12 | V | Mecanismo: :338-340, :347-349. Verificação citada: NV |
| S20 | keychain em ~/Library/Keychains, não em .cache/ | 19-22 | V | :22 |
| S21 | senha derivada do UUID de hardware; a primeira versão sorteava | 25-36 | V | :37-43. Histórico: NV |
| S22 | `find-identity` sem `-v -p codesigning` | 55-61 | V | :62-64 |
| S23 | "Criando identidade (uma vez só)" | 67 | V | :152-155 |
| S24 | RETURN não dispara em `fail`; EXIT cobre | 70-71 | V | :73-74 |
| S25 | PKCS12 do OpenSSL 3 usa MAC SHA-256, que o Security framework rejeita | 96-98 | NV | :99-101 usa `/usr/bin/openssl … -macalg sha1` |
| S26 | `-T /usr/bin/codesign` e não `-A` | 108-111 | V | :112 |
| S27 | `set-key-partition-list` evita o diálogo de keychain | 114-117 | V | Linha existe (:118-119). Efeito: NV |
| S28 | `list-keychains -s` substitui a lista; guarda-corpo | 125-133 | V | :134-148 |
| S29 | keychain travado ao fim, com ou sem erro | 160-161 | V | :162 |
| S30 | tag v1.9.2 = commit 306c88f4…; "~300 mil linhas de C++" | 179-187 | NV | Tag↔commit e contagem: rede. A conferência do commit é V (:202-209) |
| S31 | "cmake não encontrado. Rode: brew install cmake" | 190 | V | Coerente com README:27 |
| S32 | confere sempre, inclusive clone preexistente | 200-201 | V | :202-209 |
| S33 | `GGML_METAL_EMBED_LIBRARY` dispensa toolchain Metal; `GGML_BACKEND_DL=OFF`; deployment target 14.0 | 216-221 | V | Flags: :222-228. Efeitos: NV |
| S34 | lista explícita de seis `.a` | 239-240 | V | :240; Package.swift:30-31 linka os mesmos seis |
| S35 | manifesto de checksums; reuso conferido | 247-251 | V | :250, :254-257 |
| S36 | commit carimbado; `desconhecido` sem git | 280-287 | V | :288, :310 |
| S37 | `LSUIElement` fora do Dock; `NSMicrophoneUsageDescription` obrigatório | 295-297 | V | Plist: :312-314. "mata o processo": NV |
| S38 | `CFBundleShortVersionString` 0.1.0, `CFBundleVersion` 1 | 308-309 | V | Fixos, nunca mudam; a "versão" real é o commit (main.swift:538) |
| S39 | "O NeverType grava sua voz para transcrever localmente. Nenhum áudio sai da sua máquina." | 314 | V | Rede: grep vazio. O áudio fica em disco (`last.wav`, main.swift:5-9) — não sai, mas fica |
| S40 | hardened runtime fecha injeção de código | 323-326 | V | :338-340 |
| S41 | `codesign --verify --deep --strict` | 343 | V | Linha existe |
| S42 | Na primeira execução o macOS pede Microfone e Acessibilidade; depois sobrevivem aos builds | 354-356 | V | Mecanismo: main.swift:468-497. TCC: NV |

### scripts/fetch-model.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S43 | Coloca o modelo onde o app procura; construído por setup-bench.sh | 2-6 | V | :12 = Transcriber.swift:10; setup-bench.sh:198-239 |
| S44 | válido = magic hex + ≥ 50 MB | 20-23 | V | :21-22. Contradiz a regra de armadilhas.md:58-59 (A7) |
| S45 | "modelo já instalado" — idempotente | 25-29 | V | :25-29 |
| S46 | "a HuggingFace está bloqueada na rede corporativa" | 31-34 | NV | Específico do ambiente do autor; repetido em install.sh:68 e setup-bench.sh:7-9. Para quem está fora, é falso ou irrelevante |
| S47 | apaga a cópia se ela não ficar válida | 40 | V | :40 |

### scripts/install.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S48 | caminho fixo + identidade estável fazem a Acessibilidade sobreviver; mover quebra | 2-6 | NV | Tensão com build-app.sh:7-12 (idem R56) |
| S49 | recusa não-Darwin e não-arm64 | 20-21 | V | :20-21 |
| S50 | /Applications sem escrita → `cp -R build/NeverType.app ~/Applications/` | 23-28 | V | Lacuna: idem I19 |
| S51 | "Compilando (primeira vez leva alguns minutos)" | 33 | V | :32-35: só compila se `build/` não existe; build/ velho é instalado sem aviso |
| S52 | `pkill` e não `osascript`; espera o processo morrer | 39-49 | V | :47-55 |
| S53 | abrir a cópia de build/ não duplica: a segunda instância cede à primeira | 61-63 | V | main.swift:205-211 |
| S54 | "são 547 MB, e o app tem 2 MB" | 67 | NV | Precisa de build. Whisper.cpp estático + shaders embutidos (build-app.sh:226) tornam 2 MB improvável |
| S55 | na rede corporativa a HuggingFace está bloqueada | 68-69 | NV | Idem S46 |
| S56 | 400 MB, não 50 | 72-75 | V | :75 |
| S57 | promove via fetch-model.sh se existir em models/ | 77-78 | V | :77-78 |
| S58 | "setup-bench.sh # baixa e converte (~10 min)" | 83 | NV | Idem I21: três modelos, brew, python, torch |
| S59 | "copie o arquivo para $MODEL_DIR/ e pule as duas etapas acima" | 86-87 | F | Contradiz INSTALL.md:107-117 e verificar-instalacao.sh:84-85. Copiar direto pula a validação de fetch-model.sh:20-23; o app só valida ao abrir (Transcriber.swift:83), com piso de 50 MB |
| S60 | mensagem de permissões: o app pede as duas ao abrir | 95-104 | V | main.swift:468-497 |
| S61 | sem Acessibilidade "fica mudo, sem erro nenhum, parecendo quebrado" | 100-101 | F | Idem R15 |
| S62 | Como usar: ⌘ direito; tecla comum cancela | 106-109 | D | Sem duplo toque e trava (HotkeyMonitor.swift:95-97), Esc (:114-116), escolha da tecla (:150), histórico, vocabulário. README:60-102 é a versão completa |
| S63 | abre o app ao fim | 113-114 | V | `open "$DEST"` |

### scripts/record-fixture.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S64 | grava 16 kHz mono PCM 16-bit; QuickTime dá 44,1 kHz estéreo m4a | 2-4 | V | Flags: :70-73. QuickTime: NV |
| S65 | uso `<nome> [segundos] [índice-do-dispositivo]` | 7-12 | V | :18-20 |
| S66 | padrão 15 s | 19 | V | :19 |
| S67 | "ffmpeg não encontrado. brew install ffmpeg" | 25 | V | Não está em nenhum doc de requisitos |
| S68 | "janela de 10–20s da spec original foi revogada"; piso 3–120 s | 40-45 | NV | Spec: fora do repo. 3–120: V (:43-44) |
| S69 | aviso acima de 30 s | 46-49 | V | :46-49 |
| S70 | "Confira a permissão de Microfone do terminal" | 74-75 | V | ffmpeg via avfoundation depende do TCC do terminal |
| S71 | confirma 16 kHz mono via afinfo | 81-85 | V | :82 |

### scripts/setup-bench.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S72 | instala whisper-cpp, prova que o Metal carrega, constrói os modelos ggml | 2-3 | V | :41-49, :58-88, :198-239 |
| S73 | Idempotente | 5 | V | :110-127, :206-208, :223 |
| S74 | HuggingFace bloqueada; CDN da OpenAI raramente | 7-11 | NV | Idem S46 |
| S75 | "Candidatos da spec. Turbo é o favorito; small é o piso de latência" | 20 | NV | Spec fora do repo; coerente com escolha-do-modelo.md |
| S76 | sha256 dos três `.pt` | 23-25 | NV | Rede. A conferência é V (:206, :215) |
| S77 | exige Homebrew | 39 | V | `command -v brew`. Não está em README nem INSTALL.md |
| S78 | brew traz ggml com Metal no bottle | 45 | NV | Homebrew |
| S79 | cai pra CPU sem erro — "só fica ~10x mais lenta" | 53-54 | NV | Inconsistente: o resto do repo diz ~11× (README:25, INSTALL.md:48, main.swift:254, Transcriber.swift:127) |
| S80 | `for-tests-ggml-tiny.bin` e `jfk.wav` no share do Homebrew | 60-61 | NV | Layout do pacote Homebrew |
| S81 | `metal_is_active` | 63-73 | V | Idem A3 |
| S82 | magic hex; "O menor candidato quantizado tem 181 MB"; piso 50 MB | 94-103 | V | Regra: :99-108. 181 MB: NV |
| S83 | "~300 MB de torch" | 131 | NV | pip |
| S84 | proxy TLS quebra o Python; exportar o CA do sistema resolve | 139-142 | V | Código: :143-150. Efeito: NV |
| S85 | assets de openai/whisper pinados em `5f86d1d8…` | 160-164 | V | :164-173 |
| S86 | "Pinado na tag v1.9.2, a mesma versão do whisper-cpp que o Homebrew instala" | 175-179 | NV | A versão do Homebrew muda com o tempo; o download usa a TAG (:178) e o checksum (:179-192) é o que protege |
| S87 | "Se voltou 403, confira se o CDN caiu na blocklist" | 212-214 | V | Mensagem coerente com `curl --fail` |
| S88 | "O f16 é intermediário e ocupa gigabytes" | 237 | NV | Tamanho |

### scripts/verificar-instalacao.sh

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| S89 | confere de fora; NÃO verifica permissão e diz isso | 2-10 | V | :109-123 |
| S90 | sem Acessibilidade: "sem erro, sem log, sem nada" | 4-6 | F | Idem R15: há log (main.swift:495), ícone e menu |
| S91 | `/Applications/NeverType.app`; modelo em Application Support | 14-15 | V | Transcriber.swift:6-10. Lacuna ~/Applications (I19) |
| S92 | magic hex; 400 MB | 17-24 | V | :87-96 |
| S93 | `problem` acumula em vez de `fail` | 31-33 | V | :34-38, :105-107 |
| S94 | exige rodar de dentro do repositório | 43-47 | V | :46-47 |
| S95 | diagnóstico do codesign em variável, não /dev/null | 54-55 | V | :56-62 |
| S96 | "setup-bench.sh && fetch-model.sh; copiar de outra máquina precisa entrar por models/" | 83-85 | V | Coerente com INSTALL.md; contradiz install.sh:86-87 (S59) |
| S97 | "Sem Acessibilidade o app abre, mostra o ícone e não reage — sem erro nenhum" | 111-113 | F | Idem R15 |
| S98 | "encerre e reabra o app" | 121-122 | NV | Idem I29 |

## 9. Doc comments no código que afirmam comportamento

### Sources/NeverType/main.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K1 | "Um arquivo só, sobrescrito… o app não guarda histórico de nada que você falou" | 5-6 | F | `historico.json` com até 30 entradas (main.swift:161-162; TranscriptHistory.swift:23-31) e `nevertype.log` com o texto de cada transcrição da sessão (main.swift:341-344, :385). Backlog D4 cobre só o primeiro |
| K2 | Dono do modelo, carregado uma vez e mantido quente | 12 | V | :31-50 |
| K3 | É um `actor` porque o contexto do whisper.cpp é de uso serial | 14-16 | V | :20; Transcriber.swift:73-74 |
| K4 | Devolve o erro real em vez de `nil`; a versão anterior usava `try?` | 52-57 | V | :58-67. Versão anterior: NV |
| K5 | A pílula é arrastável | 73-75 | V | RecordingOverlay.swift:186-202 |
| K6 | tons gerados, não os do sistema | 77-79 | V | Tone.swift; :97-100 |
| K7 | "As notas descem quando algo termina e sobem quando algo começa ou trava" | 81-83 | V | :97-100. Impreciso: o começo é uma nota só (330 Hz), não sobe; só a trava sobe (294→392) |
| K8 | Ligado por padrão, e desligável pelo menu | 88-89 | V | :90-93, :517-522 |
| K9 | "Recriar o WAV a cada ditado seria refazer 3 KB de aritmética" | 95-96 | F | 0,085 s × 44 100 Hz × 2 B = 7,5 KB (começo e fim); 2 notas × 0,065 s = 11,5 KB (trava e descarte). Tone.swift:26-40 |
| K10 | "O tom entra pelo microfone nos primeiros ~60 ms… e o Whisper o ignora" | 104-106 | NV | Sem medição (backlog I3 já marca). O tom de começo dura 85 ms (:97), não ~60 |
| K11 | `play()` num som que ainda está tocando não reinicia | 120-121 | NV | Comportamento do AppKit; :122-123 rebobina |
| K12 | `NSStatusItem` criado em `applicationDidFinishLaunching`, depois da política | 129-134 | V | :216, :681 |
| K13 | devolve o pasteboard sempre; o texto continua alcançável; a última é a primeira do histórico | 143-155 | V | :155, :377, :539-545 |
| K14 | remove o `ultima-transcricao.txt` da versão anterior | 168-170 | V | :171-173, :215 |
| K15 | `micAuthorized` consultado; a versão anterior guardava numa flag | 175-181 | V | :182-184. Anterior: NV |
| K16 | `loginItemState` consultado; o menu se remonta a cada abertura | 186-191 | V | :192, :671-675 |
| K17 | instância única com `flock`; "3 de 3"; "1,1 GB de modelo em memória" | 195-204 | V | flock: :644-658. 3 de 3 e 1,1 GB: NV |
| K18 | O menu se remonta ao ser aberto | 218-219 | V | :671-675 |
| K19 | a pílula parada é o único sinal de que o app continua vivo | 234-235 | V | :236; RecordingOverlay.swift:245-250 |
| K20 | Carrega e aquece fora da main thread | 241-242 | V | :243 (`Task {}` para o ator) |
| K21 | O aviso de Metal só cabe se o modelo carregou | 248-250 | V | :251-258 |
| K22 | A forma muda junto com a cor | 275-277 | V | :278-280 |
| K23 | Sempre template; `contentTintColor` só tinge template | 284-290 | V | :291-293 |
| K24 | Fallback de largura com título "FF" | 294-296 | V | Existe (:296). "FF" = FalaFlow, resíduo do rename c97f01b |
| K25 | A pílula segue "trabalhando" até o texto sair | 328-330 | V | :331, :346, :353 |
| K26 | substituições rodam sobre o texto pronto | 337-338 | V | :339 |
| K27 | falha de transcrição vira sinal visível | 349-351 | V | :352-354 |
| K28 | a gravação já está rolando desde o primeiro toque | 358-359 | V | HotkeyMonitor.swift:78-80 (`.start` no primeiro `down`) |
| K29 | "Campo de senha em foco: o macOS descarta eventos sintéticos" | 383-384 | F | É flag global da sessão, como TextInjector.swift:100-102 diz; o log :385 propaga o falso positivo (backlog D3) |
| K30 | `flashIdle` volta ao ícone normal | 395-396 | V | :397-402 (2 s, se não estiver gravando) |
| K31 | texto completo no tooltip; chega ao pasteboard pelo clique | 410-411 | V | :556, :417-420 |
| K32 | commit carimbado pelo build-app.sh; mesmo valor que o atualizar.sh compara | 424-428 | V | build-app.sh:310; atualizar.sh:56 |
| K33 | API assíncrona e não closure; `Task { @MainActor in }` não resolvia | 473-483 | V | :484-487 |
| K34 | sem Acessibilidade os monitores não recebem evento; "isto é dito em voz alta" | 490-491 | V | :492-497 (ícone, log, prompt) |
| K35 | o item fala a linguagem daqui; o aviso, a da Apple | 581-582 | V | :576, :584 |
| K36 | recusa do login item vira ícone, não só log | 610-614 | V | :615-617 |
| K37 | log em stderr e arquivo; truncado a cada lançamento | 625-631 | V | :632-639; :664-668 (`createFile` com `contents: nil`) |
| K38 | fd mantido aberto pela vida do processo; fechar libera a trava | 641 | V | :642, :656 |
| K39 | sem conseguir abrir a trava, deixa rodar | 649-650 | V | :651 |
| K40 | "Acessório: sem ícone no Dock, sem janela" | 680 | D | Idem C4 (VocabularyWindow.swift) |

### Sources/NeverType/RecordingOverlay.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K41 | três estados; antes eram dois e passavam ~600 ms sem sinal | 4-8 | V | :9-13. 600 ms: NV |
| K42 | barras de nível; o ponto vermelho anterior não provava som | 15-20 | V | :22-142 |
| K43 | 18 barras | 23 | V | :23 |
| K44 | transparente ao mouse | 51-53 | V | :53 |
| K45 | verde escuro saturado; azul para transcrever | 55-68 | V | :60, :68 |
| K46 | 30 fps; `assumeIsolated` legítimo (Timer agendado na main) | 73-77 | V | :78-85 |
| K47 | sem `deinit`: nonisolated | 140-141 | V | Ausente |
| K48 | sem `isMovableByWindowBackground` para saber o fim do arrasto | 144-148 | V | :186-202, :284 |
| K49 | escura nos dois temas | 163-168 | V | :169 |
| K50 | sempre visível; a pílula parada prova que está vivo | 205-213 | V | :224-227, :245-250; main.swift:236 |
| K51 | gruda na borda a 48 pt | 221-222 | V | :222, :336-339 |
| K52 | `.floating` ficaria por baixo de apps em tela cheia | 278 | NV | AppKit; :279 usa `.screenSaver` |
| K53 | posição validada contra as telas atuais | 299-303 | V | :304-316 |
| K54 | chão e laterais = tela física; teto = `visibleFrame` | 325-332 | V | :333-339 |

### Sources/NeverType/VocabularyWindow.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K55 | primeira janela do app; precisa se ativar antes de mostrar | 4-9 | V | :39-40 |
| K56 | duas abas, dois propósitos | 11-12 | V | :58-71 |
| K57 | cópias de trabalho; "o disco só é tocado ao salvar" | 20 | V | `persist()` roda a cada edição de célula (:179, :206, :220-223) — "salvar" não é botão |
| K58 | janela de app acessório abre atrás sem `activate` | 37-38 | NV | AppKit; :39 |
| K59 | row e coluna viajam no próprio campo | 146-148 | V | :149-151 |
| K60 | salva a cada edição, não num botão | 215-219 | V | :179, :206, :225-226 |
| K61 | devolve o foco com `NSApp.hide` | 227-228 | V | :229 |

### Sources/NeverTypeCore/AudioRecorder.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K62 | Formato que o Whisper consome: 16 kHz, mono | 3 | V | :5-6; Transcriber.swift:149 |
| K63 | float32 é o que o AVAudioConverter produz | 8 | V | :10-13 |
| K64 | disco em PCM 16-bit LE; AVAudioFile converte | 16-17 | V | :18-27; teste AudioRecorderTests.swift:92-99 |
| K65 | `Error` implica `Sendable` no Swift 6; `AVAudioFormat` não é | 30-31 | V | :32-35 |
| K66 | Resampler separado: testável sem microfone | 56-59 | V | Testes :8-100 |
| K67 | uma chamada de `convert` não esgota; 8→16 kHz transbordava | 75-80 | V | `pump` :110-126. Histórico: NV |
| K68 | dreno no fim; depois do dreno o conversor não serve mais | 94-101 | V | :102-107; RecordingSink.finish :200 |
| K69 | `deepCopy` porque o buffer do tap é reaproveitado | 130-134 | V | :135-145, :357. Reaproveitamento: NV |
| K70 | RecordingSink separado; não é seguro para uso concorrente | 148-154 | V | AudioRecorder serializa por `io` (:328, :358, :396, :407) |
| K71 | amostras em memória; transcreve daqui, não do WAV; "30 s são ~1,9 MB" | 161-165 | V | main.swift:332; 30 × 16 000 × 4 B = 1,92 MB |
| K72 | `finish` idempotente | 196 | V | Teste :207-217 |
| K73 | AudioLevel puro | 215-222 | V | :223-264 |
| K74 | piso -50 dBFS; ruído de sala fica em -55 | 224-230 | V | Constante: :230. -55 medido: NV |
| K75 | fala normal fica em torno de 0,05 de RMS | 232-235 | NV | Teste :294-300 usa 0,05 |
| K76 | expoente 0,65; "fala de conversa ficava em 0,48" | 241-245 | V | :246. Aritmética bate: 20·log10(0,05) = −26 dB → (−26 + 50)/50 = 0,48 |
| K77 | versão sobre ponteiro para a thread de áudio | 256-257 | V | :258-263, :353 |
| K78 | motor nasce e morre por ditado; indicador laranja | 270-274 | V | :317-318, :388-389 |
| K79 | fila serial dona do estado; o tap só copia e despacha | 277-283 | V | :284, :357-358 |
| K80 | `onError` definido uma vez, antes da primeira gravação | 292-295 | V | main.swift:228-232 (antes de `monitor.start()`) |
| K81 | formato lido a cada `start` (fone Bluetooth muda o formato) | 314-316 | V | :326-327 |
| K82 | `defer` desfaz o motor se o start lançar | 319-322 | V | :323-324 |
| K83 | 4096 quadros ≈ 85 ms a 48 kHz; 12 níveis/s; 4 fatias | 334-345 | V | :330, :347. 4096/48 000 = 85 ms; 1/0,085 = 11,7/s |
| K84 | `append` sempre na fila de E/S | 367 | V | :358 |
| K85 | soltar a instância é o que faz o macOS liberar o microfone | 388 | NV | SO; :389 |
| K86 | `sync` como barreira; `removeTap` não garante ausência de callback | 392-394 | V | :396-400. AVFoundation: NV |
| K87 | cancelar apaga o arquivo sem deixar rastro | 404 | V | :407-408 → RecordingSink :208-211 |

### Sources/NeverTypeCore/HotkeyMonitor.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K88 | modificador puro dispensa CGEventTap | 3-8 | V | :214, :222 |
| K89 | vive na main actor | 9-10 | V | :11 |
| K90 | tecla comum durante o hold cancela | 16-17 | V | :90-92 |
| K91 | "um ditado de 31 segundos apareceu no log de uso" | 25-26 | NV | backlog.md:114 |
| K92 | toque < 250 ms; conclusão adiada até 300 ms; "não tem áudio aproveitável" | 31-36 | V | :37, :39. Áudio: NV |
| K93 | keyCode identifica a tecla; máscara identifica o lado | 133-134 | V | :140-142, :250-251; teste :107-114 |
| K94 | só modificadores puros do lado direito | 144-149 | V | :150 |
| K95 | id = keyCode, estável entre versões do macOS | 152-153 | V | :154; teste :118-123. Estabilidade: NV |
| K96 | trocar a tecla zera a máquina de estados sem reinstalar monitores | 168-173 | V | :174-181 |
| K97 | sem Acessibilidade os monitores globais não recebem eventos | 196-197 | NV | AppKit; :198-200 |
| K98 | `kAXTrustedCheckOptionPrompt` é var global rejeitada pelo Swift 6 | 204-206 | NV | Compilador; :207 usa a string |
| K99 | `assumeIsolated`: AppKit entrega na main e a ordem importa | 215-221 | V | :222-234. Contrato do AppKit: NV |
| K100 | monitor global não dispara com o app em foco; o local cobre o menu aberto | 228-230 | NV | AppKit; :231-234 |
| K101 | 53 é Escape | 254 | V | keyCode 53 = kVK_Escape |
| K102 | sem `deinit { stop() }` | 285-286 | V | Ausente |

### Sources/NeverTypeCore/LoginItem.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K103 | BTM indexa por bundle ID; medido 2026-08-28 com app-proxy; `status == .enabled` de /private/tmp | 4-15 | NV | Spike; specs/abrir-com-o-sistema.md:18-30 |
| K104 | três estados; `notRegistered` e `notFound` colapsam em `off` | 20-30 | V | :70-77; teste :23-31 |
| K105 | dois lugares; `~/Applications` porque o install.sh documenta | 50-55 | V | :62-67; install.sh:26-28 |
| K106 | regra pura como `ModelStore.isValid(magic:size:)` | 58-61 | V | :62; Transcriber.swift:44 |
| K107 | consultado toda vez que o menu se remonta | 79-83 | V | :84-86; main.swift:192 |
| K108 | recusa fora do local instalado; `build/` é reconstruído a cada compilação | 88-93 | V | :100-105; build-app.sh:291 |
| K109 | `disable` sem guarda; a baixa de qualquer cópia limpa todas (medido) | 114-119 | V | :120-130. Medido: NV |
| K110 | API e não URL; o identificador do painel já mudou | 132-136 | V | :138. Mudou: NV |

### Sources/NeverTypeCore/TextInjector.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K111 | colar e não digitar; `CGEvent` por caractere leva dezenas de ms | 4-9 | V | :152-163. Dezenas de ms: NV |
| K112 | `blockedBySecureInput`: "Campo de senha em foco" | 17-18 | F | Idem K29; o próprio arquivo corrige em :100-102 |
| K113 | cópia de todos os itens e tipos | 23-26 | V | :30-37 |
| K114 | `restoreDelay` 0,6 "generoso de propósito"; apps leem assíncrono | 50-54 | V | Constante :55. Chute sem medição: backlog D1 |
| K115 | ConcealedType; Raycast e Maccy respeitam | 57-59 | V | :60. Gestores: NV |
| K116 | duas formas de destruir dado, "reproduzidas em auditoria"; três guardas; indexado por pasteboard | 62-79 | V | :80-84, :112-143; testes :101-142. Auditoria: NV |
| K117 | entrada segura deixa o texto no pasteboard; a versão anterior retornava antes | 94-102 | V | :103-110; teste :147-168 |
| K118 | herda o retrato pendente | 114-116 | V | :117 |
| K119 | ⌘V com flags explícitas, "depois do trigger já solto" | 148-151 | V | :158-161. Ressalva: em mãos-livres o `finish` vem do `down` do toque (HotkeyMonitor.swift:110-112), o ⌘ pode estar pressionado — as flags explícitas cobrem |

### Sources/NeverTypeCore/Transcriber.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K120 | Onde o modelo mora depois de instalado | 4 | V | :8-13 = fetch-model.sh:12 |
| K121 | piso de tamanho; "O menor candidato quantizado tem 181 MB" | 15 | V | 50 MB (:25). 181 MB: NV. Contradiz armadilhas.md:58-59 (A7) |
| K122 | truncado → contexto válido → `std::out_of_range` → não abre | 17-21 | NV | Reprodução; teste :45-58 cobre a recusa |
| K123 | `is_valid_ggml` em setup-bench.sh já exigia magic e tamanho | 23-24 | V | setup-bench.sh:104-108 |
| K124 | magic little-endian, `lmgg` | 27-30 | V | :47 |
| K125 | regra separada para não escrever 50 MB por execução | 40-43 | V | :44-48 |
| K126 | "Quem usa serializa — no app, uma fila dedicada" | 71-74 | D | No app é um `actor` (main.swift:14-20), não fila |
| K127 | `ggml_backend_load_all()` removido; varria o cwd; "a auditoria provou com uma sonda" | 87-98 | V | Removido (grep vazio). Sonda: NV. Ver K152 |
| K128 | enumera dispositivos; "dezenas de linhas com metal" | 107-110 | V | :111-118 |
| K129 | CPU é cerca de 11× mais lenta, medido | 127-128 | NV | Idem R8 |
| K130 | warmUp: ganho real ~25 ms; `ggml_metal_library_init` 6,4 s frio; custa ~600 ms | 133-146 | NV | Medições. Comportamento (1 s de silêncio): V (:148-156). docs/inicializacao:21 mede 614–622 ms de aquecimento — consistente |
| K131 | prompt = `initial_prompt`; dica, não garantia | 158-160 | V | :186-189 |
| K132 | ponteiros vivos durante `whisper_full` | 172-175 | V | :184-194 |

### Sources/NeverTypeCore/TranscriptHistory.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K134 | antes só a última, em `ultima-transcricao.txt` | 14-18 | V | main.swift:164-173 remove o legado |
| K135 | teto 30; texto claro; "quem tem acesso local já lê o last.wav"; apagável pelo menu | 20-28 | V | :31, :73-80, :56-61; main.swift:560-563, :5-9 |
| K136 | acima do teto, a mais antiga sai | 30 | V | :51; teste :51-62 |
| K137 | `clear` apaga o arquivo | 58-59 | V | :60; teste :77-91 |
| K138 | ilegível começa vazio | 67-68 | V | :69; teste :94-107 |
| K139 | escrita atômica | 77-78 | V | :79 |

### Sources/NeverTypeCore/Vocabulary.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K140 | duas listas: termos → `initial_prompt`; substituições determinísticas | 14-25 | V | :60-63, :71-82 |
| K141 | origem vazia casaria com tudo; destino vazio é apagar palavra | 48-49 | V | :50; teste :83-94 |
| K142 | prompt como frase com vírgulas | 56-59 | V | :62; teste :30-36 |
| K143 | palavra inteira; ignora caixa na busca; destino literal; "família" | 65-70 | V | :74-79; testes :48-81 |
| K144 | escrita atômica | 102-103 | V | :104 |

### Sources/NeverTypeCore/Tone.swift

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K145 | tons gerados; o envelope tira o estalo | 3-12 | V | :34-35; teste ToneTests.swift:64-71 |
| K146 | sobe e desce em 25 ms | 16-19 | V | :20 |
| K147 | WAV 16-bit mono; NSSound aceita Data | 22-25 | V | :26-40; main.swift:113 |
| K148 | "produzir 3 KB de áudio" | 42-45 | F | Padrão 0,07 s × 44 100 × 2 B = 6,2 KB; os tons do app dão 7,5 KB e 11,5 KB (idem K9) |

### Package.swift e Sources/CWhisper/module.modulemap

| # | Afirmação | Linha | Classe | Evidência |
|---|---|---|---|---|
| K149 | lógica em NeverTypeCore porque executável não é importável por teste | Package.swift:4-6 | V | :12-13, :40 |
| K150 | estático; hardened runtime; "o app morria no dyld"; não exige Homebrew | Package.swift:16-27 | V | Flags :28-37; build-app.sh:168-176. Histórico: NV |
| K151 | caminhos relativos resolvidos no import | modulemap:3-4 | V | :9-10 |
| K152 | "`ggml-backend.h` entra junto porque `ggml_backend_load_all()` mora lá" | modulemap:6-7 | D | `ggml_backend_load_all()` foi removida (Transcriber.swift:87-98). O header continua necessário por `ggml_backend_dev_count/get/name` (Transcriber.swift:112-114), que também moram nele — o motivo citado é o antigo |

---

## 10. Sentido contrário: comportamento no código sem doc público

Nenhum destes aparece em README.md, CLAUDE.md, docs/*.md ou fixtures/README.md.
Ordem: primeiro o que muda o que a pessoa acredita sobre privacidade e requisitos.

| # | Comportamento | Onde no código | Onde deveria estar |
|---|---|---|---|
| B1 | **Só transcreve português.** `params.language = "pt"` fixo; sem opção no menu. `n_threads = 4` também fixo | Transcriber.swift:184-185, :168 | README (Uso, Como funciona). Para o público em inglês da etapa 2 é o primeiro fato que falta |
| B2 | **O áudio do último ditado fica em disco** (`last.wav`, sobrescrito a cada gravação, não apagado ao sair) | main.swift:5-9; AudioRecorder.swift:176, :304 | README §Histórico fala só do texto. Só o comentário TranscriptHistory.swift:27 menciona |
| B3 | **`nevertype.log` guarda o texto de toda transcrição da sessão** (e o texto "corrigido"), truncado só no lançamento seguinte; "Limpar histórico" não o toca | main.swift:341-344, :385, :450-453, :667 | README §Histórico (segunda cópia em texto claro) |
| B4 | Pílula sempre visível; arrastável; gruda na borda a 48 pt; posição persistida em `overlayOrigin` e validada contra as telas | RecordingOverlay.swift:205-343; main.swift:236 | README:75-77 diz "aparece" |
| B5 | Medidor de nível (18 barras) durante a gravação; onda azul durante a transcrição; terceiro estado "transcrevendo" | RecordingOverlay.swift:9-13, :22-142; main.swift:331 | README §Uso |
| B6 | "Copiar última transcrição" e os itens do histórico copiam SEM `ConcealedType` e sem devolver o pasteboard | main.swift:455-458 | README:146-148 promete a marca sem exceção |
| B7 | Transcrição vazia: nada inserido, nada no histórico, nenhum sinal visível (só log) | main.swift:373-375 | README §Limitações |
| B8 | Ícone `mic.slash` por 2 s após falha de inserção ou de login item, depois volta sozinho | main.swift:397-402 | README §Uso |
| B9 | Linhas do menu não listadas: "Trigger: … (segure e fale)", "dois toques travam · …", "Microfone: ok/faltando", "Acessibilidade: ok/faltando", "Modelo: …", "Versão: …", "Abrir Ajustes de Acessibilidade…", "Sair do NeverType" | main.swift:504-505, :535-538, :569, :591 | README:86-102 lista 5 itens |
| B10 | Janela de vocabulário: duas abas, botões +/–, salva a cada edição de célula, ao fechar esconde o app; arquivo `vocabulario.json` | VocabularyWindow.swift; main.swift:157-158 | README:92 diz só "duas listas"; onde fica não é dito |
| B11 | Remove `ultima-transcricao.txt` da versão anterior a cada lançamento | main.swift:164-173, :215 | Só backlog U4 |
| B12 | Prévia do histórico truncada em 44 caracteres | main.swift:412-415 | README:95-97 |
| B13 | UserDefaults `trigger`, `somDasAcoes`, `overlayOrigin` no domínio `com.nevertype.app` — fora da fronteira "Application Support" que INSTALL.md:28 declara | main.swift:86, :422; RecordingOverlay.swift:220 | INSTALL.md:28 |
| B14 | Trocar a tecla no meio de um hold zera a máquina de estados (descarta o hold) | HotkeyMonitor.swift:174-181 | Só backlog I4 |
| B15 | Esc durante o hold normal também cancela (README:63 diz "tecla comum") | HotkeyMonitor.swift:90 | README:63 |
| B16 | Monitor local mantém o trigger com o menu ou a janela do app em foco | HotkeyMonitor.swift:228-234 | — (interno, ok) |
| B17 | Aquecimento: 1 s de silêncio transcrito no lançamento | Transcriber.swift:148-156 | README:115-116 diz "mantido quente" sem dizer como |
| B18 | `CFBundleShortVersionString` fixo em 0.1.0; a versão real é o commit | build-app.sh:308-310 | README §Desenvolvimento |
| B19 | **Requisitos não listados:** `record-fixture.sh` exige `ffmpeg`; `setup-bench.sh` exige Homebrew, instala `whisper-cpp`, cria venv com `torch` (~300 MB) e baixa TRÊS checkpoints `.pt` (turbo, medium, small) — é o único caminho documentado para obter o modelo do app | record-fixture.sh:25; setup-bench.sh:39, :46, :152-157, :22-26 | README:22-30 (Requisitos); INSTALL.md:92-99 |
| B20 | `~/Applications` aceito pelo LoginItem e sugerido pelo install.sh, mas `verificar-instalacao.sh` e `atualizar.sh` só olham `/Applications` | LoginItem.swift:66; install.sh:28; verificar-instalacao.sh:14; atualizar.sh:14 | INSTALL.md:88-90 |
| B21 | `install.sh` não recompila se `build/` já existir | install.sh:32-35 | README:35-38; INSTALL.md:79 |
| B22 | Segunda instância ativa a primeira e sai | main.swift:205-211 | README (só install.sh:61-63 e armadilhas, via flock) |
| B23 | Volume dos tons fixo em 0,18; sem controle | main.swift:114 | README:90 |
| B24 | Fallback do ícone com título "FF" (FalaFlow) | main.swift:296 | Resíduo do rename c97f01b |
| B25 | `docs/inicializacao-com-o-sistema.md` e `fixtures/README.md` não são apontados por README nem CLAUDE.md | — | README §Desenvolvimento (tabela) |

## 11. Números que divergem entre documentos

| Número | Onde | Divergência |
|---|---|---|
| Lentidão sem Metal | README:25, INSTALL.md:48, escolha-do-modelo.md:94, main.swift:254, Transcriber.swift:127 dizem ~11×; setup-bench.sh:54 diz ~10x | 1 lugar fora |
| Latência por ditado | README:6 e CLAUDE.md:73 ~600 ms; README:125 ~780 ms; escolha-do-modelo.md:36 599–609 ms; backlog.md:116 ~614 ms fixos + 22 ms/s | README contradiz a si mesmo (L6 vs L125) |
| Ditado > 30 s | README:124 e escolha-do-modelo.md:71-72 "passa do teto"; backlog.md:114 mediu 1299 ms para 31 s (teto 1500) | Docs públicos vs medição no app |
| Tamanho dos WAV dos tons | main.swift:96 e Tone.swift:45 "3 KB"; cálculo dá 7,5 KB e 11,5 KB | Aritmética |
| Tom no microfone | main.swift:105 "~60 ms"; main.swift:97 duração 85 ms | Mesmo arquivo |
| Piso de tamanho do modelo | Transcriber.swift:25, fetch-model.sh:22, setup-bench.sh:103: 50 MB; install.sh:75, verificar-instalacao.sh:24: 400 MB; armadilhas.md:58-59 diz que 50 aprova truncado | Regra documentada vale em 2 de 5 |
| Momentos que exigem a pessoa | README:57 e INSTALL.md:18 "três"; INSTALL.md tem 4 marcadores | Contagem |
| Casos em que atualizar.sh para | INSTALL.md:182 "dois"; atualizar.sh tem 6 saídas por `fail` | Contagem |
| Tamanho do app | install.sh:67 "2 MB" | Sem lastro; estático com Metal embutido |
| Nome do doc de decisão | bench.sh:4, :230 `docs/decisao-modelo.md`; o arquivo é `docs/escolha-do-modelo.md` | Arquivo fantasma |
| "Sem janela" | CLAUDE.md:8, main.swift:680; VocabularyWindow.swift:4 "É a primeira janela do app" | Mesmo repo |
| 1,1 GB vs 1,2 GB | main.swift:202 e backlog.md:134 "1,1 GB" (RAM do modelo carregado); CLAUDE.md:62 "1,2 GB" (disco de `models/`, três modelos) | Coisas diferentes; não é contradição |

## 12. Fora do escopo, visto de passagem: `.vibeflow/`

- `patterns/scripts-shell.md:12, 18-19` e `index.md:74`: "os seis scripts" — são 8 (atualizar.sh e verificar-instalacao.sh). `specs/instalacao-por-agente.md:148` "os outros seis" — são 7.
- `index.md:32`: `scripts/` descrito como "bancada, build e assinatura, instalação" — falta atualização e verificação.
- `patterns/estado-do-usuario.md:87-89`: mostra `lastTranscript` com `didSet { persistTranscript() }` — hoje é propriedade computada do histórico (main.swift:155).
- `patterns/estado-consultado.md:27` cita `main.swift:126` (hoje :175-184) e `:83` cita `HotkeyMonitor.swift:52` (hoje :196-200). `patterns/verificacao-estrutural.md:54` mostra `usesMetal` só com "MTL"; o código aceita "MTL" ou "METAL" (Transcriber.swift:117).
- `conventions.md:9-10`: "nomes de arquivo em docs/ e .vibeflow/ em português" — muda na etapa 2 para docs/.
- `specs/devolucao-observada-do-pasteboard.md:81` "12 testes existentes de TextInjector" — hoje são 9 `@Test` (histórico da época; não é erro).
- Contagens do backlog conferidas e corretas: LoginItem 9, Tone 6, Trigger 4, Histórico 7, Vocabulário 12, as cinco suítes de AudioRecorderTests (5+4+7+6+9 = 31), 81 no total.
- `backlog.md` D4 continua válido (main.swift:5-6 ainda com o texto); H4 idem (README:120).

## 13. Os cinco mais graves

1. **`Sources/NeverType/main.swift:5-6`** — "o app não guarda histórico de nada que você falou", com `historico.json` (30 entradas) **e** `nevertype.log` com o texto de cada transcrição (main.swift:341-344) **e** `last.wav` com o áudio — três cópias em disco, uma delas (o log) sem doc nenhum e fora do "Limpar histórico" (K1, B2, B3).
2. **`Sources/NeverTypeCore/Transcriber.swift:25` + `scripts/fetch-model.sh:22`** — piso de 50 MB para um modelo de 547 MB, exatamente o que `docs/armadilhas.md:58-59` declara como a regra que aprova download truncado; o app abre um arquivo que o próprio doc diz derrubar o processo na primeira inferência (A7, K121).
3. **`scripts/install.sh:86-87`** — manda copiar o modelo direto para `~/Library/Application Support/NeverType/models/` "e pule as duas etapas", o oposto de `docs/INSTALL.md:107-117` e `scripts/verificar-instalacao.sh:84-85`; pula a validação e cai no item 2 (S59).
4. **`Sources/NeverTypeCore/Transcriber.swift:184-185`** — idioma fixo em `"pt"` e nenhum documento público diz que o app só transcreve português; para o leitor de fora que a etapa 2 quer atrair, é a omissão que faz o app "não funcionar" (B1).
5. **`README.md:22-30`** — Requisitos listam CLT e cmake; o único caminho documentado para o modelo (`setup-bench.sh`, INSTALL.md:97) exige Homebrew, `brew install whisper-cpp`, python3 com torch e baixa três checkpoints, não um (I21, B19, S77). Empata com `README.md:29-30` ("não precisa de nada instalado além dele", R11).

