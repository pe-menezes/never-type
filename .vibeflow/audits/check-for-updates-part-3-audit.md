# Audit Report: Check for Updates, parte 3

> Auditado em 2026-09-18, a partir de `.vibeflow/specs/check-for-updates-part-3.md`
> Diff auditado: commit d72b585 contra 6774f4c

**Verdict: PASS**

## DoD Checklist

- [x] **1. Os dois README dizem a mesma coisa, lado a lado.** `README.md` L19 a L21 e `README.pt-BR.md` L19 a L21 (a frase de abertura); `README.md` L74 a L80 e `README.pt-BR.md` L74 a L81 (Privacidade): sem requisição por conta própria; a exceção `Check for Updates…`, `git fetch` no clone de origem, só no clique; nada por timer nem ao abrir; aplicar abre o Terminal com `scripts/update.sh`; o app nunca se atualiza por dentro; os scripts baixam quando você os executa. Mesma ordem. `grep -c 'no network access during use' README.md` = 0; `grep -c 'sem acesso à rede durante o uso' README.pt-BR.md` = 0.
- [x] **2. A referência descreve o que existe.** O bloco do menu tem `Check for Updates…` entre `Start NeverType with macOS` e `Quit NeverType`; o bullet traz os três títulos de alerta (`NeverType is up to date`, `Update available`, `Could not check for updates`), os dois botões e a condição da linha; a seção da rede diz que `Process(` responde só em `UpdateCheck.swift`, com `/usr/bin/git` e `/usr/bin/open -a Terminal`, no clique, com timeout de 30 s, e que os outros padrões continuam sem resposta. `grep -c 'None of them hit' docs/reference.md` = 0. O parágrafo do `otool` e do `nm` continua como estava.
- [x] **3. `CLAUDE.md` carrega a regra nova.** L8 a L17: a exceção na mesma frase da promessa, "nothing checks on a timer or at launch", o Terminal, e a regra "the app never opens a socket on its own; network is a script's job, and scripts run in a terminal", com o ponteiro para `decisions.md`.
- [x] **4. Craftsmanship gate.** `git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio; `rather than`, `instead of` e `whereas` ausentes das linhas adicionadas. Os três títulos de alerta e os dois botões citados existem em `UpdateCheck.Outcome.title` e em `present(_:repoRoot:)`.
- [x] **5. `swift test` continua verde.** 208 testes em 25 suítes, quatro execuções; a parte é só Markdown.

## Pattern Compliance

- [x] Idioma e espelhos: inglês nos quatro arquivos; o pt-BR mudou junto com o README.
- [x] Don'ts de prosa: sem travessão, sem figura de oposição.

## Convention Violations

Nenhuma.

## Critical Gate

Limpo. Só Markdown.

2 hotfix docs not yet consolidated: `/vibeflow:audit --consolidate-hotfixes`.
