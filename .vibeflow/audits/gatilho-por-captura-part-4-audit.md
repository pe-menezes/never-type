# Audit Report: Gatilho por captura, parte 4

> Auditado em 2026-09-04, a partir de `.vibeflow/specs/gatilho-por-captura-part-4.md`
> Diff auditado: árvore de trabalho contra `efeb637` (parte 3 commitada), antes do commit desta parte

**Verdict: PASS**

## DoD Checklist

- [x] **1. A limitação antiga sumiu.** `grep -n -E "only those|three keys"
  docs/reference.md`, `grep -n "among Right" README.md` e `grep -n "Right ⌘, ⌥
  or ⌃" scripts/install.sh` não respondem nada. `CLAUDE.md` L3 a L6 nomeiam o
  painel ("chosen from the menu by pressing it"), o botão do mouse e a segunda
  tecla de mãos-livres; L11 a L12 contam a terceira janela do app.
- [x] **2. A referência descreve o que existe.** `docs/reference.md`: a seção
  Recording (L10 a L18) e a subseção "Choosing the key" (L49 a L82) com a tabela
  de nove linhas, aceito, com ressalva e recusado, cada motivo copiado do
  painel; o item **Hotkey** (L205 a L211) com a quarta linha e `Other key or
  mouse button…`; o item **Hands-free** (L214 a L224) com `Choose a hands-free
  key…`, `Change hands-free key…`, `Remove hands-free key` e o ciclo de um
  toque; a linha "Global key" (L374) com os botões do mouse; a nota sobre
  software de mouse que remapeia botões (L15 e L61).
- [x] **3. Os dois README dizem a mesma coisa.** Lidos lado a lado
  (`README.md` L27 a L34, `README.pt-BR.md` L27 a L34): quick picks, o item
  que aceita a próxima tecla, o que é aceito, a recusa com o motivo, a segunda
  tecla, as 30 transcrições e o vocabulário, o clique no círculo, a referência
  com a tabela. Mesmas afirmações, mesma ordem. As contagens de testes (154)
  mudaram juntas nos dois, e nas duas ocorrências do `CLAUDE.md`.
- [x] **4. Craftsmanship gate.** 0 travessão ou aspas curvas em linha
  adicionada nos cinco arquivos. Três pontos-e-vírgula novos na referência
  foram reescritos em frases separadas antes do commit, um deles contrastivo
  ("with none chosen; with one chosen"). Cada rótulo de item e cada frase de
  recusa ou ressalva citada existe no código: 23 literais conferidos por
  `grep -rF` em `Sources/`, todos com pelo menos uma ocorrência.
- [x] **5. `swift test` continua verde.** 154 testes em 17 suítes; a mudança
  é só de documentação, mais o texto do `install.sh`, cuja sintaxe `bash -n`
  aceita.

## Pattern Compliance

- [x] **`conventions.md`, Idioma**: `README.md` e `README.pt-BR.md` mudaram
  juntos, afirmação por afirmação. Confiança: alta.
- [x] **`conventions.md`, Don'ts**: sem travessão, sem aspas curvas, sem
  figura de oposição fazendo o trabalho do travessão nas linhas novas. Os
  pontos-e-vírgula que restam no diff são de linhas preexistentes ou de
  parênteses do `CLAUDE.md` ("Right ⌘ by default; any modifier…"), no mesmo
  molde da linha antiga. Confiança: alta.
- [x] **`verificacao-estrutural.md`, aplicado ao texto**: os DoD 1 e 4 são
  `grep` por padrão exato, e a existência de cada literal citado foi conferida
  contra o código. Confiança: alta.

## Convention Violations

Nenhuma encontrada. Achados menores, todos INFO:

- O quinto arquivo, `scripts/install.sh`, estoura em um o orçamento de
  `index.md`; autorizado pelo autor em 2026-09-04 e registrado na spec.
- `CLAUDE.md` L95 continua dizendo "Nobody besides the author has ever
  installed it". Fora do escopo desta parte; a discovery registrou uma ou duas
  pessoas testando. Vale um `/vibeflow:teach` junto com `index.md` e o backlog
  (I4), que ainda descrevem três teclas.
- `docs/INSTALL.md` e `docs/INSTALL.pt-BR.md` só nomeiam o ⌘ direito como
  padrão, que continua verdade; intocados, como a spec manda.

## Critical Gate

Clean: no destructive operations detected. Nenhum casamento do catálogo no
diff.

## Anti-escopo e orçamento

Respeitado: `docs/INSTALL.md` e `docs/INSTALL.pt-BR.md` intocados; `.vibeflow/`
só na spec desta parte (o quinto arquivo); `docs/pitfalls.md` intocado. Cinco
arquivos, com o quinto autorizado.

Ready to ship.
