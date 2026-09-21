# Audit Report: Check for Updates, parte 1

> Auditado em 2026-09-18, a partir de `.vibeflow/specs/check-for-updates-part-1.md`
> Diff auditado: `main...HEAD` (6774f4c e d72b585), mais a árvore de trabalho: os dois `static let` de timeout deixaram de ser `public` durante a auditoria

**Verdict: PASS**

## DoD Checklist

- [x] **1. A regra pura cobre as três respostas e o desconhecido.** `UpdateCheckTests`: `upToDate` (tudo igual; local à frente com instalado igual ao local; instalado igual ao remoto com o checkout atrás), `reinstallNeeded` (behind 0 e instalado diferente do local, inclusive `"unknown"`), `behind` (3 e 1 commits, carregando instalado e remoto). A regra é `decide(installed:local:remote:behind:)` em `UpdateCheck.swift`, com o alvo definido como "o commit que o `update.sh` produziria".
- [x] **2. Os desfechos de falha existem e são exercitados sem rede.** `fetchFails` (status 128 vira `.unreachable` com a saída inteira, e só uma chamada acontece), `noUpstream` (`rev-parse @{u}` com 128 vira `.noUpstream`), `badCount` (contagem não numérica vira `.unreachable`), `fourGitCalls` confere a ordem `fetch`, `rev-parse HEAD`, `rev-parse @{u}`, `rev-list --count`. O `git` entra como closure `Command`; nenhum teste usa o padrão.
- [x] **3. O timeout é real.** `timeout`: `/bin/sleep 5` com 0,3 s volta em menos de 2 s, status diferente de zero, saída `timed out after 0.3 s`. `echo`: `/bin/echo hello` volta `(0, "hello\n")`. `cannotStart`: binário inexistente volta `-1` com o caminho na saída, sem pendurar. `noTerminalPrompt`: `gitEnvironment["GIT_TERMINAL_PROMPT"] == "0"`.
- [x] **4. A linha do menu só existe com checkout alcançável.** `availability`: nil, vazio, sem `.git`, sem `scripts/update.sh`, e o caso positivo, com `exists` injetado. `MenuLayoutTests.checkForUpdatesNeedsACheckout`: sem a condição a linha não existe; com ela, `[.startAtLogin, .checkForUpdates, .quit]` fecha o menu, e com o aviso do login item `[.openLoginItems, .checkForUpdates, .quit]`. `Quit is the last line` ganhou o estado novo. Nenhuma expectativa antiga mudou: o parâmetro novo tem padrão `false`.
- [x] **5. "Update Now" é uma função com falha exercitável.** `opensTerminal`: argumentos `["-a", "Terminal", "/Users/me/never-type/scripts/update.sh"]`, nil no sucesso. `openFails`: status 1 devolve a mensagem com `bash /Users/me/never-type/scripts/update.sh` e as palavras do `open`.
- [x] **6. Nenhum `Process(` fora do runner.** `grep -n "Process(" Sources/NeverTypeCore/UpdateCheck.swift` responde uma linha, dentro de `run(_:_:timeout:environment:)`. Processos reais na suíte: `/bin/sleep`, `/bin/echo` e o caminho inexistente de `cannotStart`. Nenhum teste chama o `git` de verdade.
- [x] **7. Craftsmanship gate.** `swift build` sem warning novo (os que aparecem são de `AudioRecorder.swift` e `PasteTarget.swift`, anteriores à branch). Nas linhas adicionadas em `.swift`: nenhum `Timer`, nenhum `assumeIsolated`, nenhum `!` de desempacotamento. Doc comment em todo `public`. `git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio. Suíte: 208 testes em 25 suítes, verde em quatro execuções.

## Pattern Compliance

- [x] **`nucleo-testavel.md`**: regra em `NeverTypeCore` (`UpdateCheck`), a parte pura pública (`decide`, `isAvailable`, os textos de `Outcome`), o I/O com a chamada por parâmetro e padrão (`check(git:)`, `openUpdateScript(open:)`, `isAvailable(exists:)`), no formato de `LoginItem`. Os testes injetam tudo.
- [x] **`falha-alta.md`**: cada desfecho carrega `title` e `detail` com a saída ("run bash scripts/update.sh in a terminal"); o timeout é falha explícita com a palavra na saída; a falha do `open` devolve o comando manual.
- [x] **`estado-consultado.md`**: `isAvailable` é função de duas existências de arquivo, sem cache; quem chama (parte 2) a lê a cada rebuild do menu.
- [x] **`isolamento-tipado.md`**: nenhum `assumeIsolated`; `run` é `async` e resolve por `withCheckedContinuation`; `ProcessBox` é `@unchecked Sendable` com `NSLock`, e o doc comment diz por quê (`Process` não é `Sendable` e o watchdog roda em outra task).

## Convention Violations

Nenhuma. Um ajuste feito durante a auditoria: `fetchTimeout` e `localTimeout` eram `public` sem uso fora do módulo, contra "`public` só no que o executável ou os testes usam"; viraram internos.

## Critical Gate

- ✅ ALLOWED [SEC108, por analogia] `Sources/NeverTypeCore/UpdateCheck.swift`, `run`: processo externo (`Process()`) para `/usr/bin/git` e `/usr/bin/open`. Override: é o objeto da spec ("Runner próprio com timeout", em Decisões técnicas) e da decisão em `decisions.md` (2026-09-18), com caminho absoluto, argumentos fixos e timeout.
- ℹ️ INFO [DAT104, por analogia] `Outcome.unreachable` leva a última linha da saída do `git` ao alerta e ao log. Um remoto com credencial embutida na URL poderia aparecer ali; o repositório é público e o clone do guia é por HTTPS sem credencial. Não bloqueia.

Sem operação destrutiva no diff.

2 hotfix docs not yet consolidated: `/vibeflow:audit --consolidate-hotfixes`.

---

## Revisão de 2026-09-21 (Copilot no PR #16)

O DoD 2 acima foi marcado `[x]` com um buraco: a falha de `rev-parse --short
HEAD` não tinha teste. `falha-alta.md` diz que caminho de falha que ninguém
exercita é código morto, e a auditoria listou os quatro testes que existiam sem
conferir contra os quatro pontos de retorno do `check`. Fechado agora por
`headFails`, que confere o estágio, a saída inteira e que o upstream e a
contagem não chegam a ser perguntados.

Cinco defeitos reais vieram da mesma revisão, todos em `UpdateCheck.swift`:

- `.unreachable` virou `.gitFailed(stage:output:)`. O texto dizia sempre "git
  fetch failed" e mandava olhar a rede, inclusive quando quem falhou foi um
  `rev-parse` no checkout local.
- Todo erro do `rev-parse @{u}` virava `.noUpstream`. Medido no git 2.50.1 com
  `LC_ALL=C`, três erros diferentes caem ali, e o `--set-upstream-to` que o
  `update.sh` imprime resolve só um. `LC_ALL=C` entrou no ambiente para que a
  linha lida não dependa do idioma da máquina.
- Os dois alertas que pedem para digitar diziam `bash scripts/update.sh`. Um
  Terminal aberto pelo Finder começa em `$HOME`, onde esse comando responde "No
  such file or directory". Passaram a levar o caminho absoluto do checkout.
- O caminho no texto ia sem aspas. O `update.sh` cita `"$REPO_ROOT"` inteiro,
  então um checkout com espaço no caminho funciona — só a linha oferecida para
  colar é que não.
- O alerta podia aparecer no meio de um ditado começado durante o fetch, que
  leva até 30 s. Ele é modal e ativa o app, então o ⌘V cairia nele. A resposta
  agora espera o ditado acabar, com limite em `UpdateCheck.presentationWait`.

Um sexto achado, o de severidade alta, era falso positivo: "o timeout mata só o
`git`, e um helper (`ssh`, `git-remote-https`) seguraria o pipe aberto". Medido:
`Process` põe o filho em process group próprio (`pgid == pid`) e `terminate()`
sinaliza o grupo, como a Apple documenta. Com um helper sobrevivendo ao pai, um
`kill` cru no pid deixou a leitura presa 25 s; o `terminate()` voltou em 0,53 s,
no timeout. Está anotado em `ProcessBox.terminateIfRunning` e preso pelo teste
`timeoutWithSurvivingHelper`, para a próxima revisão não levantar de novo.

O texto do alerta citado no DoD 2 da auditoria da parte 2 é o de antes desta
revisão; a frase "Check the network" agora só aparece na falha do fetch.
