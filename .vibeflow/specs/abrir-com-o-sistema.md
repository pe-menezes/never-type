# Spec: Abrir com o sistema

> Gerado via /vibeflow:gen-spec em 2026-08-28
> A partir de `.vibeflow/prds/abrir-com-o-sistema.md`

## Objetivo

Um item no menu da bandeja liga e desliga o NeverType como login item do macOS,
para o ditado continuar funcionando depois de reiniciar a máquina.

## Contexto

O app é acessório: sem Dock, sem janela. Quando não está rodando, não deixa
rastro de ausência — você reinicia, segura ⌘ direito, e o silêncio é idêntico ao
de Acessibilidade faltando ou modelo ausente. É o modo de falha contra o qual o
projeto inteiro foi construído, sobrevivendo dentro do ciclo de vida do próprio
app. É o item nº 1 da lista de dor no `CLAUDE.md`.

O spike do discovery (2026-08-28, macOS 26.2, app-proxy assinado com a mesma
identidade `NeverType Local Signing` e o mesmo `--options runtime`) mediu quatro
coisas que definem esta spec:

1. `SMAppService.mainApp.register()` **funciona com o certificado local.** Sem
   rejeição de assinatura — a hipótese de precisar de LaunchAgent caiu.
2. **O macOS não valida o caminho do bundle.** O proxy foi registrado a partir de
   `/private/tmp/...` e o sistema respondeu `enabled`.
3. **O BTM indexa por bundle ID, não por caminho.** Registrado do `/private/tmp`,
   a cópia em `/Applications` — outro caminho, mesmo bundle ID — leu
   `status antes: enabled`. **`status` não sabe dizer qual cópia vai abrir.**
4. `unregister()` de qualquer cópia limpa o registro para todas.

O achado nº 3 é o que molda a implementação: os dois únicos sinais que a API
oferece (`register()` não lançar e `status == .enabled`) respondem "tudo certo"
sobre um bundle numa pasta temporária. Isto é `verificacao-estrutural.md` em
forma nova — a guarda tem que rodar em `Bundle.main.bundlePath` **antes** de
registrar, porque depois não existe pergunta que devolva a resposta.

## Definition of Done

1. **Abre de fato.** Com a opção ligada, depois de reiniciar a máquina e fazer
   login: o ícone do microfone está na barra, e segurar ⌘ direito insere texto.
   Verificação de olho — quem usa o app não abre terminal para conferir se ele
   abriu. `register()` sem erro e `status == .enabled` **não contam como
   evidência**: o spike mostrou os dois respondendo "ok" para um bundle em
   `/private/tmp`. (A forma checável por máquina, para a auditoria, é
   `pgrep -x NeverType`.)

2. **A guarda de caminho é exercitada de verdade.** Rodando
   `build/NeverType.app`, acionar o item não registra nada: o menu diz o motivo e
   nomeia `bash scripts/install.sh`. Confirmado abrindo em seguida o menu da
   cópia de `/Applications` e vendo que o estado não mudou.

3. **`swift test` verde**, com `Tests/NeverTypeCoreTests/LoginItemTests.swift`
   novo cobrindo, cada um com seu `@Test`:
   - os quatro casos de `SMAppService.Status` mapeados para `LoginItem.State`;
   - `isInstalledLocation` aceitando `/Applications/NeverType.app` **e**
     `$HOME/Applications/NeverType.app`, recusando qualquer outro;
   - `enable` fora do local instalado devolvendo `.refused` **sem chamar o
     registrador** (verificado por flag na closure injetada);
   - `register()` e `unregister()` que lançam virando `.refused` com a razão.

4. **O menu não guarda estado.** Desligar o NeverType em Ajustes do Sistema ›
   Itens de Início de Sessão e reabrir o menu, **sem reiniciar o app**, mostra o
   checkmark limpo.

5. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md` no
   diff. Em particular: nenhuma variável guardando o estado do login item,
   nenhum `try?` engolindo erro de `register()`, nenhum `assumeIsolated` novo,
   nenhum XCTest, nenhuma chamada de rede — o check de DoD de rede do projeto
   continua passando no código e no binário.

6. **`docs/launch-at-login.md` existe com números medidos:** o custo
   do lançamento, e o do primeiro boot com a opção ligada. O número do boot se lê
   no próprio menu, na linha `Modelo: … carga N ms`, depois de reiniciar — o app
   já mede isso sozinho, sem cronômetro e sem terminal. Sem número medido, o
   check falha; estimativa não conta.

## Escopo

- `Sources/NeverTypeCore/LoginItem.swift` (novo) — a regra e a ponte com o
  `SMAppService`, com a chamada de sistema entrando por parâmetro.
- `Sources/NeverType/main.swift` — o item de menu com checkmark, o caminho de
  `requiresApproval`, e o log de erro.
- `Tests/NeverTypeCoreTests/LoginItemTests.swift` (novo).
- `docs/launch-at-login.md` (novo) — a medição.

Quatro arquivos. No orçamento de `index.md`.

## Anti-escopo

- **Não** carregar o modelo sob demanda. O lançamento segue idêntico ao de hoje:
  547 MB e aquecimento. Se o boot doer, é tarefa separada **com o número do DoD 6
  na mão** — não otimização preventiva.
- **Não** mexer no `install.sh`. Ele continua sem fazer pergunta.
- **Não** LaunchAgent em `~/Library/LaunchAgents/`.
- **Não** relançar o app se ele morrer (`KeepAlive`).
- **Não** preferência persistida própria. O estado mora no BTM; duplicá-lo cria a
  segunda fonte de verdade que `estado-consultado.md` proíbe.
- **Não** tentar provar por código que o app abriu no login. Não dá de dentro do
  processo — a verificação é o DoD 1, e é humana.
- **Não** mexer no diálogo de Acessibilidade no boot. Ver Decisão 5.

## Decisões técnicas

### 1. A regra pura separada da chamada de sistema

`isInstalledLocation(bundlePath:home:) -> Bool` é função pura, pública, sem I/O —
mesma forma de `ModelStore.isValid(magic:size:)`, e pela mesma razão: dá para
exercitar todos os ramos sem montar bundle nenhum.

A chamada de sistema entra por parâmetro com valor padrão, como
`TextInjector.insert(secureInput:)`:

```swift
public static func state(
    bundlePath: String = Bundle.main.bundlePath,
    home: String = NSHomeDirectory(),
    read: () -> State = { State(from: SMAppService.mainApp.status) }
) -> State
```

Em produção os padrões valem e ninguém precisa saber que existem.

### 2. O caminho instalado aceita dois lugares, não um

`/Applications/NeverType.app` **e** `$HOME/Applications/NeverType.app`. O segundo
não é capricho: o `install.sh` documenta explicitamente esse fallback para máquina
gerida ou usuário não-admin, onde `/Applications` não é gravável. Uma guarda que
só aceitasse `/Applications` deixaria essa pessoa sem como ligar a opção.

### 3. `State` é enum próprio, e o mapeamento é função pura

O `SMAppService.Status` é traduzido para `LoginItem.State` numa
`public static func state(from:)`. Motivo: `Status` é tipo do sistema e o teste
precisa alimentar os quatro casos.

`Status` é `enum Status: Int`, então `Status(rawValue:)` deve permitir construir
os casos no teste. **Se não permitir**, a injeção passa a devolver `State`
diretamente e o mapeamento fica sem teste — nesse caso, registre a lacuna em
comentário em vez de fingir cobertura.

`notFound` (nunca registrado) e `notRegistered` (registrado e desligado) são
casos distintos no `Status` e colapsam no mesmo `.off` — os dois significam "não
abre com o sistema", e a interface não tem o que fazer de diferente.
`requiresApproval` é o terceiro caso e **não** colapsa: ele exige uma ação do
usuário fora do app.

### 4. `requiresApproval` abre os Ajustes pela API, não por URL

`SMAppService.openSystemSettingsLoginItems()` — e **não** uma
`x-apple.systempreferences:` montada à mão, como o item de Acessibilidade faz
hoje. A URL do painel de Itens de Início de Sessão mudou entre versões do macOS;
a API não. O item existente de Acessibilidade fica como está: fora de escopo.

### 5. O diálogo de Acessibilidade no boot fica como está

O PRD deixou isto em aberto. Decisão: não mexer.

`AXIsProcessTrustedWithOptions` com prompt só abre diálogo quando a permissão
está faltando — e a permissão foi desenhada para sobreviver aos rebuilds (é para
isso que existe o certificado estável). No caso normal, ligar a máquina não
mostra diálogo nenhum. Quando mostra, o app **realmente não funciona**, e
`falha-alta.md` é explícito: erro que o usuário não vê é erro que não existe.

Se na prática incomodar, vira tarefa separada com a evidência — não uma suposição
consumindo orçamento agora.

### 6. Rótulo: a sua expressão no item, o vocabulário da Apple no aviso

O item diz **"Abrir com o sistema"**. Mas quando o estado for `requiresApproval`,
o texto nomeia onde ir: *"desativado em Itens de Início de Sessão"* — que é como
os Ajustes do Sistema chamam, e é o que a pessoa vai procurar. Resolve as duas
metades da questão em aberto do PRD sem escolher entre elas.

## Padrões aplicáveis

- **`nucleo-testavel.md`** — a lógica vai para `NeverTypeCore`; `main.swift` só
  orquestra. Chamada de sistema entra por parâmetro com padrão, nunca `#if DEBUG`
  nem global de configuração.
- **`estado-consultado.md`** — o checkmark é propriedade computada consultando o
  sistema em `menuNeedsUpdate`, ao lado de `micAuthorized`. Nenhuma variável
  guarda o estado.
- **`falha-alta.md`** — `register()`/`unregister()` que lançam viram log **e**
  sinal visível. A mensagem nomeia a ação de saída (`bash scripts/install.sh`),
  não só o que houve.
- **`verificacao-estrutural.md`** — a guarda de caminho existe justamente porque
  o sinal disponível (`status`) é enganoso. Aplicação nova do padrão: aqui a
  evidência estrutural é o caminho do próprio bundle.
- **`isolamento-tipado.md`** — o menu é `@MainActor` e o `SMAppService` é chamado
  de lá. Nenhum `assumeIsolated` novo: não há callback de sistema neste caminho.

## Riscos

| Risco | Mitigação |
|---|---|
| `register()` passa, `status` diz `enabled`, e o app não abre no login. Os dois sinais já mentiram no spike. | DoD 1 é reboot real com `pgrep`. Nenhum outro sinal é aceito. |
| A pessoa liga a opção rodando `build/NeverType.app`, e o login item aponta para a cópia do repositório. | Guarda de caminho antes de registrar (Decisão 2), com o motivo no comentário. DoD 2 exercita. |
| `Status(rawValue:)` não construir no teste, deixando o mapeamento sem cobertura. | Decisão 3 já define o plano B e manda registrar a lacuna, não escondê-la. |
| Fantasma no BTM durante o desenvolvimento — registro de bundle que deixou de existir. | `unregister()` de qualquer cópia limpa todas (medido no spike). Desregistre antes de apagar bundle de teste. |
| `requiresApproval` não foi reproduzido no spike; o tratamento pode estar errado. | Exercitar de verdade: desligar nos Ajustes do Sistema e conferir DoD 4. Não aceitar por leitura de documentação. |
| A opção ligada torna o boot perceptivelmente mais lento por causa dos 547 MB. | DoD 6 mede em vez de supor. Se doer, tarefa separada com o número. |

## References

- `.vibeflow/prds/abrir-com-o-sistema.md` — o PRD, com o problema e o anti-escopo
- `Sources/NeverTypeCore/TextInjector.swift` — a forma de injeção a copiar (`secureInput:`)
- `Sources/NeverTypeCore/Transcriber.swift` — `isValid(magic:size:)`, a forma da regra pura
- `scripts/install.sh` — o fallback `~/Applications/` que a Decisão 2 preserva
