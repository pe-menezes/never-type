# Spec: Gatilho por captura, parte 4: documentação

> Gerado via /vibeflow:gen-spec em 2026-09-01
> A partir de `.vibeflow/prds/gatilho-por-captura.md`
> Parte 4 de 4.

## Objetivo

A documentação deixa de dizer "três teclas, e só essas" e passa a descrever o
painel, o mouse, a tabela de teclas e o segundo gatilho, nos dois idiomas.

## Contexto

Quatro lugares afirmam a limitação antiga:

- `docs/reference.md`: a seção Recording ("The menu offers three keys, ⌘, ⌥ and
  ⌃ on the right side, and only those"), o bloco do menu e os itens **Hotkey**
  e **Hands-free**, e a linha "Global key" da tabela How it works.
- `README.md`: "The menu bar menu switches the trigger key among Right ⌘, ⌥
  and ⌃", e o espelho em `README.pt-BR.md`.
- `CLAUDE.md`: "Right ⌘ by default; Right ⌥ or ⌃ from the menu".

`docs/INSTALL.md` e `docs/INSTALL.pt-BR.md` só nomeiam o ⌘ direito como padrão,
que continua verdade, e ficam como estão. `.vibeflow/index.md` menciona as três
teclas em duas linhas; `.vibeflow/` é atualizado por `/vibeflow:teach`, fora do
orçamento desta parte.

As partes 1 a 3 já estão em uso quando esta roda, então o texto descreve o que
existe, com os rótulos e as frases que o app mostra.

## Definition of Done

1. **A limitação antiga sumiu.** `grep -n -E "only those|three keys"
   docs/reference.md` não responde nada; `grep -n "among Right" README.md`
   não responde nada; a linha 4 do `CLAUDE.md` nomeia o painel e o botão do
   mouse.

2. **A referência descreve o que existe.** Em `docs/reference.md`: a seção
   Recording traz a tabela do PRD (aceito, aceito com ressalva, recusado, com o
   motivo de cada um, nas palavras do painel); o bloco do menu mostra a quarta
   linha e `Other key or mouse button…`; o item **Hands-free** descreve
   `Choose a hands-free key…`, `Change hands-free key…` e `Remove hands-free
   key`, e o ciclo de um toque; a linha "Global key" da tabela diz que botão do
   mouse entra pelo mesmo monitor em modo escuta; e a nota sobre software de
   mouse que remapeia botões está lá.

3. **Os dois README dizem a mesma coisa.** O parágrafo novo do `README.md` e o
   do `README.pt-BR.md` têm as mesmas afirmações, na mesma ordem, lidos lado a
   lado. Curto: qualquer modificador, Fn ou botão extra do mouse, escolhido no
   painel; o painel recusa e diz por quê; a tabela inteira fica na referência.

4. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md` nas
   linhas adicionadas: sem travessão nem aspas curvas
   (`git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio), e nenhuma figura de oposição fazendo o trabalho do travessão. Nenhum rótulo inventado: cada nome de item e cada frase de
   recusa citada é a que está no código.

5. **`swift test` continua verde.** A mudança é só de documentação, e a suíte é
   a prova de que nada além dela se moveu.

## Escopo

- `docs/reference.md`
- `README.md`
- `README.pt-BR.md`
- `CLAUDE.md`

Quatro arquivos.

## Anti-escopo

- **Não** muda `docs/INSTALL.md` nem `docs/INSTALL.pt-BR.md`.
- **Não** edita `.vibeflow/`. O `index.md` e o backlog (I4) são atualizados por
  `/vibeflow:teach` depois desta parte.
- **Não** escreve em `docs/pitfalls.md`, salvo se as partes 1 a 3 produziram um
  tropeço com número medido; nesse caso a entrada vai em commit próprio, fora
  deste orçamento.
- **Não** documenta o que não foi confirmado no hardware. Se Fn saiu da tabela
  na parte 1, a referência não o lista.

## Decisões técnicas

### 1. A tabela vive na referência; o README fica com um parágrafo

O README é lido por quem decide instalar, e um parágrafo basta: a tecla é
escolhida no painel, inclusive botão do mouse, e o que não serve é recusado com
o motivo. A tabela completa, com as máscaras, as ressalvas e a nota sobre
software de mouse, vai para `docs/reference.md`, que é onde já está o resto do
comportamento do gatilho.

### 2. As frases citadas são as do código

Os rótulos dos itens e as frases de recusa e ressalva são copiados de
`TriggerCapture.swift` e de `main.swift`, sem parafrasear. Quem procurar no
documento a frase que viu na tela encontra.

### 3. O `CLAUDE.md` muda uma linha

A linha de abertura passa a dizer que a tecla é escolhida no menu, entre
modificadores, Fn e botões do mouse. O resto do arquivo não fala do gatilho.

## Padrões aplicáveis

- **`conventions.md`, seção Idioma**: `README.md` e `README.pt-BR.md` mudam
  juntos.
- **`conventions.md`, Don'ts**: sem travessão, sem aspas curvas, sem figura de oposição fazendo o trabalho do travessão.
- **`verificacao-estrutural.md`**, aplicado ao texto: os DoD 1 e 4 são `grep`
  por padrão exato.

## Riscos

| Risco | Mitigação |
|---|---|
| O espelho em português diverge do inglês em uma afirmação | DoD 3 lê os dois lado a lado, afirmação por afirmação. |
| A referência descreve um rótulo que a implementação mudou | DoD 4 exige que cada frase citada esteja no código, conferida por `grep`. |
| A frase substituta do travessão instala uma antítese | O cold-read de 29/08 mediu 36 antíteses depois de zerar o travessão. Cada frase nova é afirmativa e separada. |

## References

- `.vibeflow/prds/gatilho-por-captura.md`: a tabela de teclas a transcrever
- `docs/reference.md`, seções Recording, The menu e How it works: o que muda
- `README.md` e `README.pt-BR.md`, o parágrafo do gatilho: o que muda, nos dois
- `CLAUDE.md`, linha 4: a frase de abertura

## Dependências

- .vibeflow/specs/gatilho-por-captura-part-1.md
- .vibeflow/specs/gatilho-por-captura-part-2.md
- .vibeflow/specs/gatilho-por-captura-part-3.md
