# Spec: Check for Updates, parte 2: o clique, os alertas e o Terminal

> Gerado via /vibeflow:gen-spec em 2026-09-18
> A partir de `.vibeflow/prds/check-for-updates.md`
> Parte 2 de 3.

## Objetivo

Clicar em `Check for Updates…` responde em segundos com um alerta, e `Update
Now` abre o Terminal rodando `scripts/update.sh`; o app instalado carrega o
caminho do checkout de origem para saber onde olhar.

## Contexto

A parte 1 deixou `UpdateCheck` pronto e a linha decidida em `MenuLayout`. Falta
o `main.swift` desenhar a linha, rodar a checagem no clique e mostrar o
desfecho, e falta `build-app.sh` carimbar `NeverTypeRepoRoot` no `Info.plist`,
que é como o app instalado em `/Applications` acha o clone.

O PR #14 fazia o aplicar de dentro do app, com janela de progresso, log próprio
e o pid passado ao `install.sh`. Nada disso entra: `install.sh` mata o app no
meio, e a única janela que sobrevive a isso é a do Terminal, que também é onde
as recusas do `update.sh` já são legíveis inteiras.

## Definition of Done

1. **A linha aparece no lugar certo, só quando faz sentido.** Numa instalação
   feita por `install.sh` a partir do clone, o menu mostra `Check for
   Updates…` entre `Start NeverType with macOS` e `Quit NeverType`, e
   `defaults read /Applications/NeverType.app/Contents/Info.plist NeverTypeRepoRoot`
   imprime o caminho do clone. Com o clone renomeado por um minuto, o menu
   reaberto não mostra a linha; renomeado de volta, mostra. Verificado à mão,
   com o resultado anotado no commit.

2. **Os três desfechos chegam à pessoa como alerta.** Verificados à mão, um a
   um: instalado atrás do checkout mostra "Update available" com os dois
   commits; tudo igual mostra "up to date" com o commit; com o Wi-Fi desligado
   o alerta "could not check" aparece antes do timeout de 30 s, e o app
   continua ditando depois. Cada desfecho também vira uma linha em
   `nevertype.log`, sem texto ditado.

3. **`Update Now` termina com o app novo rodando.** Com o instalado atrás,
   `Update Now` abre uma janela do Terminal que executa `update.sh`, o app fecha
   e reabre, e ao fim `defaults read ... NeverTypeCommit` é igual a
   `git rev-parse --short HEAD` do clone. A janela do Terminal fica aberta com
   a linha `ok updated to <commit>`.

4. **Nada roda sozinho.** `grep -n "UpdateCheck" Sources/NeverType/main.swift`
   só aparece em `rebuildMenu`, no `item(for:)` e nas ações do clique; nenhum
   `Timer`, nenhuma chamada em `applicationDidFinishLaunching`. `nevertype.log`
   de um launch sem clique não contém `update`.

5. **Segundo clique durante a checagem é ignorado com registro.** Uma linha em
   `nevertype.log` diz que a checagem anterior ainda roda; o mesmo para um
   clique durante gravação ou transcrição, com o traço de dois segundos do
   ícone, a resposta que `toggleLoginItem` já dá a uma recusa.

6. **O carimbo sobrevive a caminho com `&`.** A expressão de escape do
   `build-app.sh`, rodada sobre `/Users/a&b/<c>`, imprime
   `/Users/a&amp;b/&lt;c&gt;`, e `plutil -lint` aprova o `Info.plist` do bundle
   montado.

7. **Craftsmanship gate.** `swift build` sem warning novo; o salto para a main
   actor é `Task { @MainActor in }`, sem `assumeIsolated`; o alerta é
   `NSAlert` no mesmo formato de `showAccessibilityRequiredAlert`; nenhuma
   violação dos Don'ts de `conventions.md` nas linhas adicionadas, travessão e
   aspas curvas incluídos.

## Escopo

- `Sources/NeverType/main.swift`
- `scripts/build-app.sh`

Dois arquivos.

## Anti-escopo

- **Não** cria `UpdateProgressWindow` nem log de update: o Terminal é a
  janela.
- **Não** toca `scripts/install.sh` nem `scripts/update.sh`: rodando no
  Terminal, o app não é ancestral do script e o `pkill -x NeverType` de sempre
  enxerga a instância. O caminho por `NEVERTYPE_CALLER_PID` do PR #14 não
  entra.
- **Não** guarda preferência nem "Later": `Later` fecha o alerta e pronto.
- **Não** desativa a hotkey durante a atualização: quem clicou `Update Now`
  está olhando o Terminal, e o app fecha em segundos.
- **Não** mexe nos docs (parte 3).

## Decisões técnicas

- **Rebuild do menu lê `UpdateCheck.isAvailable(repoRoot:)`**, com o caminho
  vindo de `Bundle.main` a cada chamada, como `buildCommit` já faz. Nenhum
  `let` no delegate guardando a resposta.
- **O clique roda a checagem numa `Task { @MainActor in }`** e mostra o
  `NSAlert` ao voltar. O alerta é modal e ativa o app, como o de
  Acessibilidade: é uma ação que a pessoa iniciou, e a resposta tem de
  aparecer na frente do que ela estava olhando.
- **Guarda de ocupado e de ditado no clique.** Um `Bool` no delegate, zerado
  no fim da `Task`, ignora o segundo clique; gravação ou transcrição em curso
  recusa com `render(.blocked)` e `flashIdle()`, o mesmo sinal da recusa do
  login item. A checagem em si não toca áudio, mas o alerta modal roubaria o
  foco do app onde o texto ia ser colado.
- **`Update Now` chama `UpdateCheck.openUpdateScript`**, que roda
  `/usr/bin/open -a Terminal <root>/scripts/update.sh`. Falha do `open` vira
  um segundo alerta com o comando manual. O Terminal é o da Apple, sempre
  presente, e `open` não passa pelo TCC de Automação, ao contrário do
  `osascript` que `conventions.md` proíbe.
- **`NeverTypeRepoRoot` no plist, com escape XML** de `&`, `<` e `>` por
  `sed`. O PR #14 interpolava o caminho cru: um clone em pasta com `&` produz
  plist inválido e o app não abre. `$COMMIT` segue sem escape porque é hex.

## Padrões aplicáveis

- `estado-consultado.md`: disponibilidade lida no rebuild.
- `isolamento-tipado.md`: `Task { @MainActor in }` para voltar do `await`.
- `falha-alta.md`: cada desfecho tem alerta e linha de log; recusa de clique
  tem sinal visível.
- `scripts-shell.md`: o carimbo segue o esqueleto do script, com comentário do
  porquê e do que quebrava.

## Riscos

- **`open -a Terminal` abre o `.sh` num editor em vez de executar.** Verificado
  no DoD 3 antes de fechar. Se acontecer, o fallback é um `scripts/update.command`
  de uma linha que chama `update.sh`, dentro do mesmo orçamento.
- **Perfil do Terminal configurado para fechar a janela quando o shell sai
  limpo.** O sucesso some da tela; a falha, com saída diferente de zero, fica.
  O app reaberto é a prova do sucesso; documentado na parte 3.
- **Ditado iniciado durante o alerta** (a hotkey continua viva): a colagem cai
  no alerta, que não tem campo de texto, e o histórico guarda o texto. Aceito.
- **Proxy do shell ausente dentro do app**: o fetch falha com "could not
  check", cuja mensagem manda rodar o script no Terminal, onde o proxy existe.

## Dependencies

- .vibeflow/specs/check-for-updates-part-1.md

## References

- https://github.com/pe-menezes/never-type/pull/14 : os textos de alerta e o
  carimbo `NeverTypeRepoRoot` em `build-app.sh`.
- `Sources/NeverType/main.swift`, `showAccessibilityRequiredAlert` e
  `toggleLoginItem`: o formato do alerta e o sinal de recusa a copiar.
