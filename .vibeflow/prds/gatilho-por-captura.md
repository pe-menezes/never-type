# PRD: Gatilho por captura

> Gerado via /vibeflow:discover em 2026-09-01

## Problema

Quem testou o NeverType pediu para escolher a própria tecla. O pedido veio de
uma ou duas pessoas e em três formas: uma tecla que não está entre as três
oferecidas, a experiência de escolher apertando a tecla, que Wispr Flow e afins
ensinaram, e um botão do mouse. Ninguém disse que não achou o submenu Hotkey. O
que não serve é a lista.

A lista é ⌘, ⌥ e ⌃ direitos, e só. A limitação tem motivo escrito em
`HotkeyMonitor.Trigger.all`: o app escuta o teclado sem interceptar, então só
serve tecla que sozinha não digita nada nem dispara nada no app da frente. Um
modificador puro atende a isso. Uma letra, um F5 ou o Caps Lock chegariam ao app
da frente junto com o NeverType, e engolir o evento pede o `CGEventTap` que o
projeto recusou no I1 do backlog.

A arquitetura permite bem mais do que a lista oferece. Os dois lados de ⌘, ⌥, ⌃
e ⇧, a tecla Fn e os botões extras do mouse chegam pelo mesmo `NSEvent` em modo
escuta. O pedido, lido com essa fronteira na mão, é: tudo que a arquitetura
suporta, escolhido pelo gesto que as pessoas já conhecem, e o resto recusado
dizendo por quê.

Nem todo modificador serve, porque um início em falso custa caro. Apertar o
gatilho liga o microfone, toca o tom de início e mostra o pill na hora, e o
cancelamento toca o tom de descarte (`main.swift`, ciclo do ditado). Um gatilho
que participa de atalho do dia a dia vira dois tons e um piscar do microfone a
cada ⌘C. É esse custo que decide a tabela abaixo.

## Público

Quem instala o NeverType e chega com um hábito de outro app de ditado, ou com um
teclado e um mouse diferentes dos do autor. Hoje, uma ou duas pessoas entre as
que testaram. O autor segue no ⌘ direito e não sente diferença nenhuma.

## Solução proposta

Um painel de captura, aberto do menu, que aceita a próxima tecla ou botão
apertado e o torna o gatilho.

- No submenu **Hotkey**, abaixo das três teclas de sempre, um item **Other key
  or mouse button…** abre um painel pequeno com uma frase: aperte a tecla ou o
  botão que você quer usar.
- Aceito: o painel fecha, o gatilho muda na hora, a escolha é guardada, e todo
  lugar que ensina o gesto passa a nomear o novo gatilho: título do menu,
  submenu de mãos-livres, tooltip do ícone e do orb.
- Aceito com ressalva: o painel mostra a ressalva numa linha e só fecha depois
  de ela ser confirmada.
- Recusado: o painel mostra o motivo numa linha e continua esperando.
- Esc fecha sem mudar nada. Enquanto o painel está aberto, o gatilho atual não
  grava: apertar a tecla atual para reescolhê-la iniciaria um ditado.
- Um gatilho de fora da lista aparece marcado como quarta linha do submenu,
  acima do item de captura.
- Um gatilho só. Escolher é substituir.

**Botão do mouse.** Qualquer botão além dos dois primeiros, com o mesmo gesto do
teclado: segurar grava, soltar transcreve, dois cliques travam em mãos-livres,
Esc descarta. O clique continua chegando ao app da frente, e o painel diz isso
ao aceitar.

**Segundo gatilho, para mãos-livres.** No submenu **Hands-free**, um item abre o
mesmo painel para escolher um gatilho de liga e desliga: um toque trava em
mãos-livres, o toque seguinte transcreve, Esc descarta. Mesma tabela, mesma
recusa, e o gatilho principal é recusado para esse papel. Vem vazio por padrão,
e o item que o define também o remove. O duplo toque do gatilho principal
continua existindo e continua sendo o que o título do menu ensina.

**A tabela do painel:**

| Resultado | Gatilho | Motivo, como aparece na tela |
|---|---|---|
| Aceito | ⌘, ⌥ e ⌃ direitos; ⌃ esquerdo; botão do mouse a partir do terceiro | |
| Aceito com ressalva | Fn | O macOS abre o seletor de emoji ao tocar Fn sozinho, salvo com "Não Fazer Nada" em Ajustes do Sistema > Teclado. Teclado de terceiros pode tratar Fn no firmware, e aí o macOS nunca vê a tecla |
| Aceito com ressalva | ⌥ esquerdo | Em layout americano é a tecla dos acentos, e cada acento iniciaria e cancelaria uma gravação |
| Aceito com ressalva | Botão do mouse | O clique continua chegando ao app da frente. Num navegador, o botão 4 é voltar |
| Recusado | Tecla comum, ou combinação com tecla comum | Chegaria ao app da frente: o app escuta sem interceptar |
| Recusado | ⇧ dos dois lados | Cada maiúscula iniciaria e cancelaria uma gravação |
| Recusado | ⌘ esquerdo | Cada atalho iniciaria e cancelaria uma gravação |
| Recusado | Caps Lock | Alterna o estado do teclado, e não tem segurar |
| Recusado | Clique principal e secundário | Todo clique iniciaria uma gravação |

## Critérios de sucesso

Todos observáveis de fora do processo:

1. A pessoa que pediu escolhe a tecla ou o botão sem instrução e dita de ponta a
   ponta com ele: segura, fala, solta, e o texto aparece no app da frente. Dois
   toques travam, um toque transcreve.
2. Sair e abrir o app de novo mantém o gatilho escolhido, inclusive botão do
   mouse.
3. Tecla recusada no painel não muda nada: o gatilho é o mesmo, nenhuma
   gravação começa, e o motivo está na tela.
4. Com o painel aberto, apertar o gatilho atual não grava.
5. Com o segundo gatilho definido, um toque trava em mãos-livres com o pill
   mostrando a trava, e o toque seguinte transcreve.
6. Quem tinha uma escolha guardada pela versão anterior abre a nova e continua
   com a mesma tecla.

## Escopo v0

- Item **Other key or mouse button…** no submenu Hotkey, e o painel de captura.
- A tabela acima como regra pura e testável, com o motivo de cada recusa e de
  cada ressalva como texto de interface.
- `Trigger` generalizado: qualquer modificador dos dois lados, Fn, e botão do
  mouse a partir do terceiro, com rótulo derivado (Right ⌘, Left ⌃, Fn, Mouse
  button 4) e identificador estável que continua lendo o que a versão anterior
  gravou.
- Botão do mouse no `HotkeyMonitor`, com o mesmo gesto do teclado.
- Segundo gatilho de mãos-livres, opcional, definido e removido do submenu
  Hands-free pelo mesmo painel.
- Gatilho atual suspenso enquanto o painel está aberto.
- Todo texto que nomeia o gatilho continua passando por um único ponto de
  mudança.
- Documentação: `docs/reference.md`, os dois README e o `CLAUDE.md` deixam de
  dizer "três teclas, e só essas".

## Anti-escopo

- **Não** interceptar eventos (`CGEventTap`). A decisão do I1 continua: um
  callback lento congela a entrada do sistema inteiro. É o que fecha a porta
  para letra, F-key e combinação, e a porta fica fechada.
- **Não** adotar `KeyboardShortcuts` nem outra dependência SPM. Decisão fechada
  no backlog.
- **Não** vários gatilhos de push-to-talk ao mesmo tempo, o "+" do Wispr Flow.
  Um gatilho principal e um de mãos-livres, cada um único.
- **Não** combinação com tecla comum para mãos-livres, o "⌥ Space" do Wispr
  Flow. ⌥ Space insere espaço inflexível em campo de texto do macOS, é apertado
  duas vezes por ditado, e é o atalho padrão de Raycast e Alfred. Sem
  interceptar, o app não evita nada disso.
- **Não** janela de ajustes. O painel nasce e morre no gesto.
- **Não** clique principal, secundário, nem clique com modificador como gatilho.
- **Não** remapear nada no sistema, nem pedir Monitoramento de Entrada além do
  que o app já tem.
- **Não** mudar o gesto: segurar, soltar, duplo toque e Esc continuam iguais
  para tecla e para botão.
- **Não** mudar o padrão. ⌘ direito continua sendo o gatilho de quem nunca
  escolheu.

## Contexto técnico

**O que existe:**

- `HotkeyMonitor.Trigger` (`Sources/NeverTypeCore/HotkeyMonitor.swift`):
  `keyCode`, `deviceMask`, `label` e a lista `all` com as três teclas. O `id` é
  o keyCode em texto, guardado em `UserDefaults` sob a chave `trigger`
  (`main.swift`) e restaurado por `Trigger.named` no lançamento. O identificador
  novo precisa continuar lendo esse formato.
- `HotkeyMonitor.handle` filtra `.flagsChanged` pelo keyCode e lê o lado pela
  máscara. Botão do mouse entra pelos mesmos dois monitores, com
  `.otherMouseDown` e `.otherMouseUp` na máscara e filtro por `buttonNumber`
  (o `NSEvent` conta do zero: 2 é o terceiro botão).
- `HotkeyMonitor.Latch` é a máquina de estados pura do gesto, com 9 testes.
  Botão do mouse mapeia direto em `.down` e `.up`. O segundo gatilho pede
  entrada nova (um toque trava, o seguinte encerra), na mesma máquina ou numa
  irmã, igualmente pura e testada.
- `chooseTrigger` (`main.swift`) é hoje o único ponto que muda o gatilho, e é o
  que mantém título do menu, submenu e tooltip (`refreshHoverHint`) dizendo a
  tecla certa. O backlog já avisa que um segundo caminho deixaria o tooltip
  errado sem sinal nenhum. O painel desemboca nesse mesmo método.
- `MenuLayout.rows` e `MenuLayoutTests` decidem quais linhas o menu tem. A
  quarta linha marcada e o item de captura entram por ali.
- `VocabularyWindow.show()` é o precedente de janela num app acessório:
  `NSApp.activate(ignoringOtherApps: true)` antes de `makeKeyAndOrderFront`, e
  o foco volta ao app anterior ao fechar. Com o painel à frente, o monitor
  global não dispara e o local sim, e o local já está instalado por causa do
  menu.
- `PointerGesture` e `PasteTarget.decide` são o molde da regra de captura: uma
  função pura, de evento para aceito, aceito com ressalva, recusado com motivo
  ou cancelado, exercitável sem teclado, sem mouse e sem janela.

**Máscaras e keyCodes conhecidos**, a confirmar apertando cada tecla, porque a
regra do projeto é verificar o efeito:

| Tecla | keyCode esq / dir | máscara esq / dir |
|---|---|---|
| ⌘ | 55 / 54 | 0x0008 / 0x0010 |
| ⌥ | 58 / 61 | 0x0020 / 0x0040 |
| ⌃ | 59 / 62 | 0x0001 / 0x2000 |
| ⇧ | 56 / 60 | 0x0002 / 0x0004 |
| Fn | 63 | `.function` (0x800000) |
| Caps Lock | 57 | `.capsLock` (0x10000) |

**Padrões que a implementação segue:**

- `nucleo-testavel.md`: tabela e regra de captura em `NeverTypeCore`, puras. O
  painel em `Sources/NeverType/` só desenha e encaminha.
- `isolamento-tipado.md`: `HotkeyMonitor` é `@MainActor`, e o painel também.
  `assumeIsolated` só nos monitores, como hoje, pela ordem dos eventos.
- `falha-alta.md`: recusa e ressalva são texto na tela. Painel que fecha em
  silêncio é erro.
- `estado-do-usuario.md`: o painel não engole evento de outro app. O monitor
  local devolve `nil` só para evento que nasceu com o painel em foco.
- `verificacao-estrutural.md`: a máscara de cada tecla é confirmada pelo evento
  real, e o teste compara valores.

**Testes:** as suítes do gatilho vivem hoje em `AudioRecorderTests.swift`
(backlog H5). As suítes novas vão para `HotkeyMonitorTests.swift`. Mover as
antigas é o H5 e fica a critério da spec.

**Orçamento:** não cabe em 4 arquivos. É subsistema novo, o caso que o
`index.md` prevê. Corte sugerido para o gen-spec, cada parte dentro de 4
arquivos:

1. `Trigger` generalizado, botão do mouse e compatibilidade do identificador,
   com testes.
2. Regra de captura, painel e itens de menu.
3. Segundo gatilho de mãos-livres.
4. Documentação.

## Questões em aberto

- **Como a ressalva se confirma.** Fn, ⌥ esquerdo e botão do mouse são aceitos
  com uma linha de aviso. Falta decidir se o painel espera um segundo aperto da
  mesma tecla, um clique em OK, ou fecha sozinho depois de mostrar. O critério é
  a ressalva ser lida antes de o gatilho valer.
- **Fn em teclado de terceiros.** Se o teclado trata Fn no firmware, o painel
  nunca recebe evento e a pessoa fica esperando. Esc já é a saída; falta
  decidir se o painel diz algo depois de alguns segundos sem evento. Ninguém
  mediu quantos teclados fazem isso.
- **Botão do mouse e a regra "tecla comum cancela".** Segurando o botão, uma
  tecla comum cancela como hoje, por uniformidade. A justificativa original, a
  tecla significa "isso era um atalho", não vale para mouse. Fica igual no v0.
- **Toque longo no segundo gatilho.** O gatilho de mãos-livres é de toque.
  Decidir na spec se segurar conta como um toque na descida ou é ignorado.
- **Texto dos itens de menu.** "Other key or mouse button…" e o item do
  Hands-free são propostas. O texto final é de interface e fecha na spec.
