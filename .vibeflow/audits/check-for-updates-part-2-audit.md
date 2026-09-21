# Audit Report: Check for Updates, parte 2

> Auditado em 2026-09-18, a partir de `.vibeflow/specs/check-for-updates-part-2.md`
> Diff auditado: `main...HEAD` (6774f4c a 6b36c65); `Sources/NeverType/main.swift` e `scripts/build-app.sh`
> Primeira rodada às 05h, PARTIAL com os cliques pendentes; fechada às 10h com o exercício à mão do autor no app instalado

**Verdict: PASS**

## DoD Checklist

- [x] **1. A linha aparece no lugar certo, só quando faz sentido.** Captura do autor às 09h56: `Check for Updates…` entre `Start NeverType with macOS` e `Quit NeverType`. Com o clone renomeado (`mv never-type never-type-x`) a linha sumiu do menu; com o nome de volta, voltou (relato às 09h41). `defaults read /Applications/NeverType.app/Contents/Info.plist NeverTypeRepoRoot` imprime `/Users/pedromenezess/Projects/apps/never-type`; `plutil -lint` aprova.
- [x] **2. Os três desfechos chegam à pessoa como alerta.** Capturas do autor às 09h11 e 09h27: `Update available`, "The checkout is at e3e6ffa and the installed app is 6774f4c. Update Now opens Terminal and runs scripts/update.sh, which rebuilds and reinstalls; NeverType quits and reopens at the end."; `NeverType is up to date`, "Running e3e6ffa. Nothing newer on the remote."; com o Wi-Fi desligado, `Could not check for updates`, "git fetch failed: fatal: unable to access 'https://github.com/pe-menezes/never-type.git/': Could not resolve host: github.com. Check the network, or run bash scripts/update.sh in a terminal.", em segundos, e o ditado funcionou depois. `nevertype.log`: uma linha por clique, `upToDate(installed: "e3e6ffa")` duas vezes e `unreachable("fatal: unable to access ...")`, sem texto ditado.
- [x] **3. `Update Now` termina com o app novo rodando.** Duas vezes pelo botão. 09h26: instalado `6774f4c`, `update.sh` no Terminal ("Repository already at e3e6ffa; only the reinstall is missing"), build em 3,83 s, "Quitting the running instance", `verify-install.sh` com "running (pid 89210)", `ok updated to e3e6ffa`. 09h56: `e3e6ffa` para `6b36c65`, build em 2,13 s, pid 90522, `ok updated to 6b36c65`. Nas duas, a janela do Terminal ficou aberta com o log inteiro até `[Process completed]`, e `NeverTypeCommit` no plist passou a ser o commit do checkout.
- [x] **4. Nada roda sozinho.** `grep -n "UpdateCheck" Sources/NeverType/main.swift`: um doc comment, o `rebuildMenu` (`isAvailable`) e as duas ações (`check`, `openUpdateScript`). Nenhum `Timer` novo, nada em `applicationDidFinishLaunching`. `nevertype.log` do launch: 6 linhas, zero com `update`; as linhas de `check for updates` só aparecem depois de cada clique.
- [x] **5. Segundo clique e clique durante ditado são ignorados com registro.** Clique com um mãos-livres travado, 09h27: nenhum alerta, a gravação seguiu, `nevertype.log` com `check for updates: ignored, dictation in progress`; o sinal visível é o traço no ícone da barra, o mesmo da recusa do login item. Segundo clique: com o alerta na tela, o menu abre com todos os itens desabilitados (captura às 09h56), o macOS segura o clique antes da guarda. A guarda `updateCheckInProgress` cobre a janela do fetch, cerca de um segundo, e desde `6b36c65` também o alerta; a linha `ignored, a check is still running` não foi produzida à mão, porque o caminho até ela está fechado pelo AppKit.
- [x] **6. O carimbo sobrevive a caminho com `&`.** `printf '%s' '/Users/a&b/<c>' | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'` imprime `/Users/a&amp;b/&lt;c&gt;`; `plutil -lint` no plist do bundle instalado: OK.
- [x] **7. Craftsmanship gate.** `swift build` sem warning novo; o salto é `Task { @MainActor in }` nas duas ações; o alerta segue `showAccessibilityRequiredAlert` (`NSApp.activate`, `NSAlert`, `alertStyle`, `addButton`, `runModal`); zero travessão ou aspas curvas nas linhas adicionadas. Suíte verde em sete execuções, 208 testes.

## O que o exercício à mão achou

A guarda de ocupado era zerada antes de o alerta subir, então um clique com o alerta na tela abriria um segundo fetch e um segundo alerta atrás do primeiro. Corrigido em `6b36c65`: a guarda só cai depois do `runModal`. Na prática o AppKit já desabilita o menu durante o alerta; a correção vale para a ordem dos eventos e para o dia em que isso mudar.

## Pattern Compliance

- [x] **`estado-consultado.md`**: `repoRoot` é `static var` computada do `Bundle` a cada uso; `updateCheckAvailable` é lido no `rebuildMenu`. O teste do clone renomeado é a prova: a linha some e volta sem reabrir o app.
- [x] **`isolamento-tipado.md`**: `Task { @MainActor in }` para voltar do `await`; nenhum `assumeIsolated`.
- [x] **`falha-alta.md`**: cada desfecho vira alerta e linha de log, os três vistos; a recusa de clique tem o traço de dois segundos; a falha do `open` tem alerta próprio com o comando manual; o caminho "sem carimbo", inalcançável pelo menu, escreve no log.
- [x] **`scripts-shell.md`**: o carimbo em `build-app.sh` tem comentário com o porquê e o que quebrava (PR #14, caminho cru no plist).

## Convention Violations

Nenhuma.

## Critical Gate

Limpo. `build-app.sh` adiciona uma variável escapada por `sed`; `main.swift` adiciona chamadas ao Core. Sem operação destrutiva.

2 hotfix docs not yet consolidated: `/vibeflow:audit --consolidate-hotfixes`.
