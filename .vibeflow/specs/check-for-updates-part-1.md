# Spec: Check for Updates, parte 1: a regra e o git, em Core

> Gerado via /vibeflow:gen-spec em 2026-09-18
> A partir de `.vibeflow/prds/check-for-updates.md`
> Parte 1 de 3.

## Objetivo

O menu ganha a linha `Check for Updates…` como decisão testável, e o Core passa a
saber comparar instalado, local e remoto e a rodar o `git` com timeout, tudo
com a chamada de sistema entrando por parâmetro.

## Contexto

Hoje a comparação dos três commits vive só em `scripts/update.sh`. O PR #14
reimplementou isso em `AutoUpdater.swift`, no alvo executável, com `Process()`
direto no tipo: nada dali tem teste, e a única cobertura são as linhas do menu.
`nucleo-testavel.md` manda a regra para `NeverTypeCore`, com a chamada de
sistema por parâmetro e valor padrão, no formato de `LoginItem` e
`FocusHandback`.

O que muda de decisão em relação ao PR: a pergunta "precisa atualizar?" deixa
de ser `local != remote || installed != local`, que oferece um "b07c6da →
b07c6da" quando o instalado está atrás de um checkout já igual ao remoto, e
passa a distinguir três respostas: atualizado, reinstalar (o checkout já tem o
commit, o app não) e atrás em N commits. Branch à frente do remoto conta como
atualizada, porque `git pull --ff-only` não faria nada.

## Definition of Done

1. **A regra pura cobre as três respostas e o desconhecido.** Em
   `UpdateCheckTests`: `decide(installed:local:remote:behind:)` devolve
   `.upToDate` com tudo igual; `.upToDate` com local à frente e instalado igual
   ao local (behind 0); `.reinstallNeeded` com behind 0 e instalado diferente do
   local, inclusive `"unknown"`; `.behind(commits:)` com behind maior que zero,
   carregando instalado e remoto.

2. **Os desfechos de falha existem e são exercitados sem rede.** Com um `git`
   falso injetado: fetch com status diferente de zero vira `.unreachable` com a
   saída do comando dentro; `rev-parse @{u}` falhando vira `.noUpstream`; o
   caminho feliz roda `fetch`, `rev-parse HEAD`, `rev-parse @{u}` e `rev-list
   --count HEAD..@{u}` nessa ordem, e o teste confere a ordem.

3. **O timeout é real, não intenção.** `UpdateCheck.run` com `/bin/sleep 5` e
   limite de 0,3 s volta antes de 2 s com status diferente de zero e a palavra
   `timed out` na saída; com `/bin/echo` volta status 0 e a saída. O ambiente
   do runner de git carrega `GIT_TERMINAL_PROMPT=0`, conferido no teste pela
   propriedade que o expõe.

4. **A linha do menu só existe com checkout alcançável.** `isAvailable`
   responde falso para caminho nulo, para diretório sem `.git`, e para
   diretório sem `scripts/update.sh`; verdadeiro com os dois presentes, com o
   `exists` injetado. Em `MenuLayoutTests`, com `updateCheckAvailable: true` a
   linha `.checkForUpdates` fica entre o bloco do login item e `.quit`; com
   falso, não existe, e os testes atuais passam sem mudar nenhuma expectativa.

5. **"Update Now" é uma função com falha exercitável.** `openUpdateScript`
   chama o comando injetado com `["-a", "Terminal", "<root>/scripts/update.sh"]`
   e devolve nil no sucesso; com status diferente de zero devolve a mensagem
   que nomeia o comando manual, `bash <root>/scripts/update.sh`.

6. **Nenhum `Process(` fora do runner.** `grep -n "Process(" Sources/NeverTypeCore/UpdateCheck.swift`
   responde só dentro de `run(_:_:timeout:environment:)`, e nenhum teste chama
   o `git` de verdade: os únicos processos reais da suíte são `/bin/echo` e
   `/bin/sleep`.

7. **Craftsmanship gate.** `swift build` sem warning novo nos arquivos tocados;
   nenhum `!` fora de literal; nenhum `MainActor.assumeIsolated`; doc comment
   em todo `public` dizendo o porquê; nenhuma violação dos Don'ts de
   `conventions.md` nas linhas adicionadas, travessão e aspas curvas incluídos
   (`git diff -U0 | grep -E '^\+.*(—|–|“|”)'` vazio).

## Escopo

- `Sources/NeverTypeCore/UpdateCheck.swift` (novo)
- `Tests/NeverTypeCoreTests/UpdateCheckTests.swift` (novo)
- `Sources/NeverTypeCore/MenuLayout.swift`
- `Tests/NeverTypeCoreTests/MenuLayoutTests.swift`

Quatro arquivos, no orçamento.

## Anti-escopo

- **Não** toca `main.swift`, `build-app.sh` nem docs (partes 2 e 3).
- **Não** persiste nada: nenhuma chave em `UserDefaults`, nenhum "dismissed
  SHA", nenhum horário de última checagem. O clique é a única memória.
- **Não** agenda nada: nenhum `Timer`, nenhuma checagem no launch.
- **Não** aplica nada de dentro do app: nenhuma chamada a `update.sh` por
  `Process`; o Core só sabe pedir ao `open` que o Terminal rode o script.
- **Não** reimplementa as recusas do `update.sh` (mudança não commitada, branch
  divergida): elas continuam no script, que é onde a pessoa as lê.

## Decisões técnicas

- **Um tipo, `UpdateCheck`, no formato de `LoginItem`.** `enum` sem estado,
  funções estáticas, a chamada de sistema como parâmetro com padrão. O que é
  regra (`decide`, `isAvailable`, as mensagens de `Outcome`) é puro e público;
  o que é I/O (`check`, `openUpdateScript`, `run`) recebe o comando injetado.
- **`Outcome` carrega o texto do alerta.** `title`, `detail` e `offersUpdate`
  são propriedades do desfecho, como `LoginItem.Outcome.refused` carrega a
  razão já escrita. O executável só desenha. Cada mensagem de falha nomeia a
  saída: "run bash scripts/update.sh in a terminal", como `falha-alta.md` pede.
- **"Atrás" por `git rev-list --count HEAD..@{u}`**, não por desigualdade de
  SHA. Desigualdade confunde "à frente" com "atrás" e oferece rebuild inútil
  todo dia numa máquina com commit local não enviado. Custo: um comando a mais,
  local e instantâneo.
- **Runner próprio com timeout**, `withCheckedContinuation` mais uma `Task`
  que dorme o limite e chama `terminate()` se o processo ainda vive.
  `Process` não é `Sendable`; ele viaja numa caixa `@unchecked Sendable` cuja
  única operação é `terminate`. Trinta segundos para o `fetch`, dez para os
  comandos locais. Sem isso, uma rede que descarta pacotes deixaria o clique
  pendurado sem resposta, que é o oposto de `falha-alta.md`.
- **`GIT_TERMINAL_PROMPT=0`** no ambiente do git: sem terminal, um remoto que
  pede credencial ficaria esperando até o timeout. Com a variável, falha na
  hora e a mensagem diz o que houve.
- **Binários por caminho absoluto**, `/usr/bin/git` e `/usr/bin/open`: app
  aberto pelo Finder não tem o `PATH` do shell.
- **Disponibilidade por existência de arquivo**, `.git` e `scripts/update.sh`
  no caminho carimbado, conferida a cada rebuild do menu. É `stat`, não
  processo: barato o bastante para a regra de `estado-consultado.md`, que
  proíbe guardar. O PR #14 rodava `git rev-parse` uma vez no launch e guardava.
- **`Command` é `@Sendable ([String]) async -> CommandResult`.** O `git` já
  vem ligado ao `-C <root>` e ao timeout; o `open` recebe os argumentos
  inteiros. Uma assinatura para os dois, e o teste falso é um closure.

## Padrões aplicáveis

- `nucleo-testavel.md`: regra em Core, sistema por parâmetro, pura separada do
  I/O.
- `falha-alta.md`: cada desfecho tem texto com a saída; timeout é falha
  explícita, não espera infinita.
- `estado-consultado.md`: disponibilidade conferida na hora, nunca guardada.
- `isolamento-tipado.md`: nada de `assumeIsolated`; o runner é `async` e
  quem chama decide o ator.

## Riscos

- **`terminate()` num processo que já saiu** entre a checagem e a chamada:
  `Process.terminate` num processo terminado não lança, só é ignorado; o teste
  do `/bin/echo` com timeout longo cobre a ordem normal, e o do `/bin/sleep`
  cobre o timeout.
- **`readDataToEndOfFile` depois do timeout**: com o processo morto por
  `SIGTERM` o pipe fecha e a leitura volta. Se um neto do processo segurasse o
  pipe, a leitura penduraria; `git fetch` não deixa netos vivos.
- **Saída maior que o buffer do pipe** bloqueia o filho antes de terminar. Os
  quatro comandos produzem linhas curtas; `fetch --quiet` produz nada.

## References

- https://github.com/pe-menezes/never-type/pull/14 : o código a portar,
  `performCheck`, `promptToUpdate`, `showInfo` e os textos dos alertas.
- `scripts/update.sh:56-70`: a comparação dos três commits que a regra imita.
- `Sources/NeverTypeCore/LoginItem.swift` e `Tests/NeverTypeCoreTests/LoginItemTests.swift`:
  o formato a copiar, chamada de sistema por parâmetro e cada ramo com teste.
