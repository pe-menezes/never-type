# PRD: Abrir com o sistema

> Gerado via /vibeflow:discover em 2026-08-28

## Problema

Um app de menu bar que não está rodando não avisa que não está rodando. Você
reinicia o Mac, segura ⌘ direito, e não acontece nada — exatamente o mesmo
sintoma de Acessibilidade faltando, de microfone negado e de modelo ausente. O
projeto inteiro é construído contra esse modo de falha (`falha-alta.md`,
`verificacao-estrutural.md`), e mesmo assim o ciclo de vida do próprio app ainda
tem ele.

Hoje o único jeito de voltar a ditar depois de reiniciar é lembrar de abrir o
NeverType à mão — e nada na tela lembra você disso, porque um app acessório sem
janela e sem Dock não deixa rastro de ausência. O `CLAUDE.md` já lista isto como
o item nº 1 do que falta, na ordem de dor.

## Público

Quem já tem o NeverType instalado e usa como ferramenta de todo dia — hoje, o
autor. De tabela, a primeira pessoa que instalar isto sem ser ele: o `install.sh`
conduz microfone e Acessibilidade, e depois o app some no primeiro reboot.

## Solução proposta

Um item no menu da bandeja, **"Abrir com o sistema"**, com checkmark, que
registra e desregistra o NeverType como login item do macOS. Padrão desligado:
quem instalou não pediu para o app entrar sozinho na inicialização.

O estado do checkmark é lido do sistema toda vez que o menu abre — nunca guardado
numa variável (`estado-consultado.md`). O usuário pode desligar pelos Ajustes do
Sistema sem avisar o app, e o menu tem que contar a verdade.

## Critérios de sucesso

Um só, e é de fora do processo: **depois de ligar a opção, reiniciar a máquina e
fazer login, `pgrep -x NeverType` responde um pid, e segurar ⌘ direito dita.**

Nenhuma outra evidência conta. O spike mostrou que `register()` retorna sem erro
e `status` responde `enabled` para um bundle que está numa pasta temporária — ou
seja, os dois sinais que a API oferece podem dizer "tudo certo" sobre uma
instalação que não existe.

## Escopo v0

- Item de menu "Abrir com o sistema" com checkmark, alternando o registro.
- Estado consultado ao sistema em `menuNeedsUpdate`, junto com microfone e
  Acessibilidade.
- **Guarda de caminho:** recusa registrar se `Bundle.main.bundlePath` não for
  `/Applications/NeverType.app`, com mensagem dizendo o que fazer
  (`bash scripts/install.sh`). Ver Contexto técnico para o porquê.
- Os quatro estados do `SMAppService.Status` refletidos em texto honesto:
  `enabled`, `notRegistered`, `notFound`, e `requiresApproval` — este último
  precisa de um item que abra os Ajustes do Sistema, igual ao que já existe para
  Acessibilidade.
- Erro de `register()`/`unregister()` vai para o log e para o ícone, nunca
  engolido.
- Medir e registrar em `docs/` o custo real da inicialização: tempo até o ícone
  aparecer e até o primeiro ditado responder, num boot com a opção ligada.

## Anti-escopo

- **Não** carregar o modelo sob demanda. O app segue carregando os 547 MB e
  aquecendo no lançamento, como hoje. Se o boot doer, vira tarefa separada **com
  o número medido na mão** — não otimização preventiva.
- **Não** mexer no `install.sh`. Ele continua não fazendo pergunta nenhuma.
- **Não** LaunchAgent em `~/Library/LaunchAgents/`. O spike derrubou a hipótese
  de que seria necessário.
- **Não** relançar o app automaticamente se ele morrer (`KeepAlive`). É outro
  problema.
- **Não** tentar provar por código que o app abriu no login. Não dá de dentro do
  processo; a verificação é humana e é o critério de sucesso.
- **Não** adicionar preferência persistida própria. O estado mora no BTM do
  macOS, e duplicá-lo criaria a segunda fonte de verdade que o
  `estado-consultado.md` proíbe.

## Contexto técnico

**Medido no spike (2026-08-28, macOS 26.2, app-proxy assinado com a mesma
identidade `NeverType Local Signing` e o mesmo `--options runtime`):**

1. `SMAppService.mainApp.register()` **funciona com o certificado local.** Sem
   rejeição de assinatura. O risco que podia invalidar a abordagem inteira caiu.
2. **O macOS não valida o caminho do bundle.** O proxy foi registrado a partir de
   `/private/tmp/...` e o sistema respondeu `enabled`.
3. **O BTM indexa por bundle ID, não por caminho.** Registrado do `/private/tmp`,
   a cópia em `/Applications` — outro caminho, mesmo bundle ID — leu
   `status antes: enabled`. **`status` não sabe dizer qual cópia vai abrir.**
   É daí que sai a guarda de caminho: ela tem que rodar em
   `Bundle.main.bundlePath` **antes** de registrar, porque depois não há como
   perguntar.
4. `unregister()` de qualquer cópia limpa o registro para todas.
5. `notFound` (nunca registrado) e `notRegistered` (registrado e desligado) são
   casos distintos do enum, os dois significando "não abre com o sistema".
6. `sfltool dumpbtm` trava sem privilégio, e `launchctl print gui/$UID` não lista
   login item de app. Não há verificação por script do estado do BTM — mais uma
   razão para o critério de sucesso ser o reboot.

**Por que a guarda de caminho importa neste repositório em particular:** o
`build-app.sh` monta `build/NeverType.app` e o `install.sh` copia para
`/Applications`. As duas cópias têm o mesmo bundle ID e a mesma assinatura.
Abrir a de `build/` por engano já é um tropeço conhecido — o `install.sh` avisa
sobre isso na linha do `warn`. Com login item, o tropeço passa a ser permanente e
silencioso.

**Padrões que a implementação segue:**

- `estado-consultado.md` — o checkmark é propriedade computada consultando
  `SMAppService.mainApp.status`, igual ao `micAuthorized`.
- `nucleo-testavel.md` — a lógica vai para `NeverTypeCore` com a chamada de
  sistema entrando por parâmetro, para os testes poderem exercitar cada caminho
  de falha. O `CLAUDE.md` é explícito: caminho de falha não exercitável não conta
  como implementado.
- `falha-alta.md` — `register()` que lança vira log e ícone `.blocked`, não
  `try?`.
- `isolamento-tipado.md` — o menu é `@MainActor`; `SMAppService` é chamado de lá.
  Sem `assumeIsolated`.

**Orçamento:** cabe em ≤4 arquivos — `LoginItem.swift` novo em `NeverTypeCore`,
`main.swift`, o teste, e a nota de medição em `docs/`.

## Questões em aberto

- **O rótulo.** "Abrir com o sistema" é a sua expressão. A Apple chama de "item
  de início de sessão", e os Ajustes do Sistema usam esse vocabulário — se o
  usuário for procurar onde desligar, vai procurar por ele. Decidir antes da
  spec.
- **`requiresApproval` não foi reproduzido no spike.** É o estado de quem
  desligou nos Ajustes do Sistema. O tratamento está no escopo, mas o caminho
  precisa ser exercitado de verdade na implementação — não aceito por leitura de
  documentação.
- **O que fazer se a Acessibilidade estiver faltando no momento do boot.** Hoje o
  lançamento chama `requestAccessibilityPermission()`, que abre diálogo do
  sistema. Ligado na inicialização, isso vira um diálogo toda vez que você liga o
  Mac. Provavelmente o caminho de boot deve ser mais quieto — mas isso é decisão
  de spec.
