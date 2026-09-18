# Audit Report: Check for Updates, parte 2

> Auditado em 2026-09-18, a partir de `.vibeflow/specs/check-for-updates-part-2.md`
> Diff auditado: `main...HEAD` (6774f4c e d72b585); `Sources/NeverType/main.swift` e `scripts/build-app.sh`

**Verdict: PARTIAL**

O que produz o PARTIAL, em uma linha: tudo que dá para verificar sem clicar foi verificado, o caminho do Terminal inclusive, de ponta a ponta; os cliques do DoD (a linha no menu, os três alertas, o botão "Update Now", as duas recusas) ficam para a mão do autor, e item não verificado é FAIL por regra.

## DoD Checklist

- [ ] **1. A linha aparece no lugar certo, só quando faz sentido.** Verificado: `defaults read /Applications/NeverType.app/Contents/Info.plist NeverTypeRepoRoot` imprime `/Users/pedromenezess/Projects/apps/never-type`; `plutil -lint` aprova o plist. Pendente à mão: abrir o menu e ver `Check for Updates…` entre `Start NeverType with macOS` e `Quit NeverType`; renomear o clone por um minuto e ver a linha sumir. A regra da posição tem teste na parte 1.
- [ ] **2. Os três desfechos chegam à pessoa como alerta.** Pendente à mão. O que a máquina do autor mostra hoje ao clicar, previsto pelos mesmos comandos que o app roda: instalado `6774f4c`, checkout `d72b585`, `git rev-list --count HEAD..@{u}` = 0, logo `Update available` com "The checkout is at d72b585 and the installed app is 6774f4c". `nevertype.log` recebe uma linha por desfecho (`log("check for updates: \(outcome)")`), sem texto ditado.
- [ ] **3. `Update Now` termina com o app novo rodando.** O comando que o botão dispara, `/usr/bin/open -a Terminal <root>/scripts/update.sh`, foi executado à mão em 2026-09-18 com o instalado em `17a7ff2` e o checkout em `6774f4c`: a janela do Terminal abriu, o `update.sh` rodou ("only the reinstall is missing"), o processo antigo (pid 43853) morreu, o novo (84412) subiu em 10 s, `NeverTypeCommit` = `6774f4c`, `codesign --verify --deep --strict` ok, `nevertype.log` com a linha `ready.`. O botão em si, ainda não clicado.
- [x] **4. Nada roda sozinho.** `grep -n "UpdateCheck" Sources/NeverType/main.swift`: um doc comment, o `rebuildMenu` (`isAvailable`) e as duas ações (`check`, `openUpdateScript`). Nenhum `Timer` novo, nada em `applicationDidFinishLaunching`. `nevertype.log` do launch do app novo: 6 linhas, zero com `update`.
- [ ] **5. Segundo clique e clique durante ditado são ignorados com registro.** Código presente em `checkForUpdates` (`updateCheckInProgress`, `recorder.isRecording`, `transcriptionSession.isTranscribing`, com `render(.blocked)` e `flashIdle()`), linhas de log escritas. Não exercitado à mão.
- [x] **6. O carimbo sobrevive a caminho com `&`.** `printf '%s' '/Users/a&b/<c>' | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'` imprime `/Users/a&amp;b/&lt;c&gt;`; `plutil -lint` no plist do bundle instalado: OK.
- [x] **7. Craftsmanship gate.** `swift build` sem warning novo; o salto é `Task { @MainActor in }` nas duas ações; o alerta segue `showAccessibilityRequiredAlert` (`NSApp.activate`, `NSAlert`, `alertStyle`, `addButton`, `runModal`); zero travessão ou aspas curvas nas linhas adicionadas.

## Pattern Compliance

- [x] **`estado-consultado.md`**: `repoRoot` é `static var` computada do `Bundle` a cada uso; `updateCheckAvailable` é lido no `rebuildMenu`.
- [x] **`isolamento-tipado.md`**: `Task { @MainActor in }` para voltar do `await`; nenhum `assumeIsolated`.
- [x] **`falha-alta.md`**: cada desfecho vira alerta e linha de log; a recusa de clique tem o traço de dois segundos; a falha do `open` tem alerta próprio com o comando manual; até o caminho "sem carimbo", inalcançável pelo menu, escreve no log.
- [x] **`scripts-shell.md`**: o carimbo em `build-app.sh` tem comentário com o porquê e o que quebrava (PR #14, caminho cru no plist).

## Convention Violations

Nenhuma.

## Critical Gate

Limpo. `build-app.sh` adiciona uma variável escapada por `sed`; `main.swift` adiciona chamadas ao Core. Sem operação destrutiva.

## Gaps

- **DoD 1, 2, 3 e 5: os cliques.** O que falta é a mão do autor no app instalado, que já é a build `6774f4c` desta branch:
  1. Abrir o menu: `Check for Updates…` acima de `Quit NeverType`. (DoD 1)
  2. Clicar: alerta `Update available`, "The checkout is at d72b585 and the installed app is 6774f4c". (DoD 2)
  3. `Update Now`: o Terminal abre com o `update.sh`; o app fecha e reabre; `defaults read /Applications/NeverType.app/Contents/Info.plist NeverTypeCommit` passa a `d72b585`. (DoD 3)
  4. Clicar de novo: `NeverType is up to date`, "Running d72b585". (DoD 2)
  5. Com o Wi-Fi desligado, clicar: `Could not check for updates` antes de 30 s, e ditar em seguida. (DoD 2)
  6. Clicar duas vezes seguidas, e uma vez durante um ditado em mãos-livres: `nevertype.log` com "ignored". (DoD 5)
  7. Renomear o clone por um minuto: a linha some do menu; renomear de volta, ela volta. (DoD 1)
  Esforço: S, dez minutos.

## Incremental Prompt Pack

Não há código a escrever: os sete passos acima, anotados neste relatório com o resultado, fecham a parte. Se algum falhar, é `/vibeflow:hotfix` com o relato.

2 hotfix docs not yet consolidated: `/vibeflow:audit --consolidate-hotfixes`.
