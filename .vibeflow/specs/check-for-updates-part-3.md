# Spec: Check for Updates, parte 3: a promessa reescrita

> Gerado via /vibeflow:gen-spec em 2026-09-18
> A partir de `.vibeflow/prds/check-for-updates.md`
> Parte 3 de 3.

## Objetivo

Os docs deixam de afirmar "nenhuma requisição de rede" sem ressalva e passam a
dizer a exceção exata, com a regra que a limita: rede só no clique, aplicar só
no Terminal.

## Contexto

Quatro lugares carregam a promessa: `README.md` (linhas 20 e 74, com o espelho
em `README.pt-BR.md`), a seção "The check behind no network at run time" de
`docs/reference.md`, que ainda diz que o grep por `Process(` não acha nada, e
o `CLAUDE.md`, que abre com a restrição absoluta. A referência também descreve o
menu linha a linha e precisa da linha nova. O PR #14 atualizou só a referência e
deixou os outros três contradizendo o código; o Copilot apontou.

`docs/INSTALL.md` e o espelho descrevem o caminho do agente, `bash
scripts/update.sh`, que continua igual. Ficam fora desta parte. `.vibeflow/`
(o Don't de rede em `conventions.md`, a entrada em `decisions.md`) foi
atualizado por `/vibeflow:teach` antes da parte 1.

## Definition of Done

1. **Os dois README dizem a mesma coisa, lado a lado.** A frase de abertura e
   o parágrafo de Privacidade afirmam, na mesma ordem: o app instalado não faz
   requisição de rede, com uma exceção que a pessoa dispara, `Check for
   Updates…`, que roda `git fetch` no clone de origem só no clique; aplicar
   abre o Terminal com `scripts/update.sh`; nada roda sozinho.
   `grep -n "no network access during use" README.md` e
   `grep -n "sem acesso à rede durante o uso" README.pt-BR.md` não respondem.

2. **A referência descreve o que existe.** Em `docs/reference.md`: o bloco do
   menu mostra `Check for Updates…` entre `Start NeverType with macOS` e
   `Quit NeverType`, com o bullet dos três desfechos e do Terminal; a seção da
   rede diz que o grep por `Process(` responde só em `UpdateCheck.swift`, para
   `/usr/bin/git` e `/usr/bin/open`, ambos no clique, e que o `otool`/`nm`
   continuam sem registro. `grep -n "None of them hit" docs/reference.md` não
   responde.

3. **`CLAUDE.md` carrega a regra nova.** O parágrafo de rede diz a exceção e a
   regra que a limita: o app nunca abre socket por conta própria; rede é coisa
   de script, e script roda no Terminal. `grep -n "No network calls at run time" CLAUDE.md`
   não responde na forma antiga, sem a exceção na mesma frase.

4. **Craftsmanship gate.** Nenhum travessão nem aspas curvas nas linhas
   adicionadas (`git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio), e nenhuma
   figura de oposição fazendo o trabalho do travessão. Cada nome de item e cada
   frase de alerta citada é a que está no código da parte 2.

5. **`swift test` continua verde.** A parte é só de documentação.

## Escopo

- `README.md`
- `README.pt-BR.md`
- `docs/reference.md`
- `CLAUDE.md`

Quatro arquivos.

## Anti-escopo

- **Não** toca `docs/INSTALL.md`, `docs/INSTALL.pt-BR.md` nem o bloco "How to
  use" de `scripts/install.sh`. O caminho do agente não mudou; a linha do menu
  entra neles num commit próprio depois, se o autor quiser.
- **Não** edita `.vibeflow/`: já foi por `/vibeflow:teach`.
- **Não** escreve em `docs/pitfalls.md`, salvo se as partes 1 e 2 produziram
  tropeço com número medido; nesse caso, commit próprio.

## Decisões técnicas

- **A exceção é dita inteira onde a promessa era dita inteira.** Uma frase
  curta no README, o mecanismo completo na referência. Quem lê só o README
  sabe que existe um clique que toca a rede; quem quer o comando exato acha
  na referência.
- **A regra vai no `CLAUDE.md` como regra, não como nota.** É o que um agente
  lê antes de codar, e é o lugar de dizer "nunca socket por conta própria" para
  o próximo PR não repetir o #14.

## Padrões aplicáveis

- `conventions.md`, idioma e mirrors: inglês, pt-BR em par.
- Don'ts de prosa: sem travessão, sem figura de oposição.

## Riscos

- **Frase de README que promete menos do que o código faz**, ou mais. O DoD 1
  amarra as afirmações à lista do PRD; a parte 2 é a fonte dos textos.

## Dependencies

- .vibeflow/specs/check-for-updates-part-2.md
