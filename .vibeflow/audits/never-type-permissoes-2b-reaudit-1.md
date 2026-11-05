# Reauditoria 1 · never-type-permissoes · parte 2b

05/11/2026. Base do conserto `72f5f8d`, rodada não commitada. Estado auditado: `main.swift` 57034112, `StatusIcon.swift` c3c55c01, `MenuLayoutTests.swift` db86b113, `docs/reference.md` 3f5a251f, os mesmos do progresso, conferidos por `shasum` no começo e depois das sabotagens. `<rascunho>` abaixo é `<rascunho da sessão>`.

## Veredito: PASS

L1, L3, L6 e L7 fecharam. O conserto mudou uma linha de código, a do L1, e não trouxe defeito. Ficam dois achados baixos, N1 e N2, que não seguram o PASS e viram tarefa. O app não foi rodado: o caso real depende do TCC e está no teste manual, no fim.

## Achados do conserto

| achado | estado | prova |
|---|---|---|
| L1, a linha `permissions:` em `settleIcon` | **fechado** | `main.swift` 949 a 951; L1-GONE, L1-AFTER, L1-REREAD e L1-CONST morrem em `settleIconWiring`; cenário abaixo |
| L3, `transcriptionEndWiring` até o `}` do `switch` | **fechado** | FAIL-AFTER, que sobrevivia na auditoria, morre em `transcriptionEndWiring`; FAIL-FLASH também |
| L6, a frase da atualização recusada | **fechado** | `docs/reference.md` 323 a 327, conferida contra o código abaixo |
| L7, os comentários | **fechado, com N1** | as frases falsas saíram e nenhuma cópia sobrou; o texto novo deixou o N1 |

### L1
Com o conserto, a perda vai para o log antes do desenho, e a volta sai pela releitura, porque a última linha escrita agora é a da perda.

* **Nenhuma leitura a mais:** os dois argumentos vêm de `reading`, e os valores padrão de `logPermissionsIfChanged` só valem quando o argumento falta. L1-REREAD, a forma sem argumentos, morre.
* **Nenhuma linha nova com tudo concedido:** `lineIfChanged` deduplica (`Permissions.swift` 168 a 174).
* **Quem lê a linha:** `scripts/verify-install.sh` 152 lê a última `permissions:` do log, no mesmo formato. O conserto não atrapalha: a última linha fica mais próxima do estado real depois de uma perda e volta.

### L6
A frase está certa nos dois casos do guard de `checkForUpdates`, `main.swift` 1336 a 1341:
* na gravação, `.released` chama `settleIcon` (457), e o risco sai no fim da gravação;
* na transcrição, o sucesso chama `settleIcon` (502), e o risco sai no fim dela;
* o `.failure` deixa o `.blocked` dele (510), que é o sinal da falha;
* antes disso, os 2 s de `flashIdle` não desenham nada, porque `StatusIcon.redraw` devolve nil durante o ditado.

Nenhuma outra cópia da frase em `README.md`, `README.pt-BR.md`, `docs/` ou `Sources/`. A 309, do login recusado, e a 151 ficam, porque valem em repouso, como a auditoria mediu.

### Perímetro
O diff de `Sources/` sem comentários é só a linha do L1 (`git diff 72f5f8d -- Sources`, filtrado). `Tests/NeverTypeCoreTests/Audit/`, `scripts/` e os documentos de instalação não mudaram. Os dois comentários fora do perímetro do conserto, `logPermissionsIfChanged` e `main.swift` 1334, são os que o briefing desta reauditoria lista no L7, e a frase da 1334 diz o mesmo que a do L6. L2, L4 e L5 seguem como decididos e não foram reabertos.

## Achados novos

### N1 · baixo · o "those paths" passou a apontar para as exceções
`main.swift` 925 e 926 e `StatusIcon.swift` 115 e 116. O conserto do L7 pôs as duas exceções logo antes da frase que já existia:

> except on a transcription failure or a recorder error, which draw the slash on purpose. Those paths drew the normal icon without this rule

Lida como está, a frase diz que a falha e o erro do gravador desenhavam o ícone normal. Não desenhavam: em `ab0a2a2`, antes da parte, o `.failure` já tinha `self.render(.blocked)` (503 a 505). Os caminhos a que a frase se refere são os fins de ditado que passam por `settleIcon`. Só comentário e sem efeito no app, mas é o tipo de frase que o L7 tirava. Conserto: trocar "those paths" por "the ends of a dictation", nos dois lugares.

### N2 · baixo · o progresso diz que o git ignora `.vibeflow/`, e não ignora
`.vibeflow/progresso/never-type-permissoes-2b.md` 128. `git check-ignore` não casa nem o progresso nem este relatório (saída 1), e o `git status --short` mostra o progresso como modificado, ao contrário da frase. O que muda na prática: `.vibeflow/` entra no commit e no repositório público, e a contagem "os quatro arquivos e `models`" daquela linha está uma linha curta. Não afeta código. Registro para corrigir a frase quando a orquestração commitar a rodada.

## Cenário do L1

`AppDelegate` mora no alvo executável, que teste não importa, então o cenário usa as classes reais do Core (`PermissionLog`, `PermissionWatch`, `PermissionReading`) e reproduz as chamadas de `settleIcon` e `permissionsChanged`. Sem TCC e sem relógio. Em `<rascunho>/reaudit2b/cenario/main.swift`:

```
swiftc -swift-version 5 -suppress-warnings Sources/NeverTypeCore/StatusIcon.swift Sources/NeverTypeCore/Permissions.swift <rascunho>/reaudit2b/cenario/main.swift -o <rascunho>/reaudit2b/cenario/cenario
```

| caso | sequência medida |
|---|---|
| com a linha do conserto, perda e volta | `permissions: ... accessibility=granted`, `permissions: ... accessibility=missing`, ícone, `permissions: ... accessibility=granted`, ícone |
| sem a linha (o L1 da auditoria) | `permissions: ... accessibility=granted`, ícone, ícone |
| tudo concedido, 5 ditados com 2 chamadas cada | 1 linha `permissions:`, a da abertura, e a releitura não sobe |

O segundo caso reproduz o L1 como a auditoria o descreveu, e o primeiro mostra que ele saiu.

**Sonda nenhuma entrou na suíte.** O briefing não dá arquivo de testes para esta reauditoria, e o conserto não pede: o cenário roda uma cópia das duas funções do app, então não protege a ligação, que quem prende é `settleIconWiring`. A parte do Core já está presa em `PermissionsPart1AuditTests` 52 a 56 (perda e volta na mesma `PermissionLog`) e em `everyReturnIsDelivered`. As sondas da auditoria não mudaram, e nenhuma caiu.

## Sabotagens

`python3 -I <rascunho>/reaudit2b/sab.py`: troca exata com contagem 1, `swift build`, `swift test --filter MenuLayoutTests`, volta por cópia conferida por `shasum` depois de cada uma. Todas com build verde. Final 57034112.

| id | sabotagem | resultado |
|---|---|---|
| FAIL-AFTER | `self.settleIcon()` depois do `self.render(.blocked)` do `.failure` | morre, `transcriptionEndWiring` |
| FAIL-FLASH | `self.flashIdle()` no mesmo lugar | morre, `transcriptionEndWiring` |
| L1-GONE | `settleIcon` sem a linha | morre, `settleIconWiring` |
| L1-AFTER | a linha depois do `renderResting` | morre, `settleIconWiring` |
| L1-REREAD | `logPermissionsIfChanged()`, com leitura própria | morre, `settleIconWiring` |
| L1-CONST | `accessibility: true` | morre, `settleIconWiring` |

Por decisão do briefing (fricção #86), não procurei formas novas de esconder código do oráculo de texto.

## Comandos e resultado

| comando | resultado |
|---|---|
| `shasum` nos quatro arquivos, no começo e depois das sabotagens | iguais aos do progresso |
| `swift build` | Build complete |
| `swift test`, antes das sabotagens | 317 testes em 34 suítes, verde |
| `python3 -I <rascunho>/reaudit2b/sab.py` | 6 mortas, 0 vivas, restaurado |
| `<rascunho>/reaudit2b/cenario/cenario` | as três sequências acima, `OK` |
| `swift test`, depois das sabotagens | 317 testes em 34 suítes, verde |
| `swift build --build-tests --scratch-path <rascunho>/reaudit2b/limpo` e `python3 scripts/count-swift-warnings.py` | 4, a mesma lista (`AudioRecorder.swift` 1:1, 402:29 e 402:41; `PasteTarget.swift` 159:28), em pasta nova |
| `git check-ignore -v` no progresso e neste relatório | saída 1, nenhum ignorado (N2) |

A contagem de warnings repetiu porque a do executor foi antes das duas últimas trocas de comentário. Nada de `tccutil`, de script de instalação, de keychain nem de git de escrita.

## Para o teste manual do Pedro

Substitui a seção da auditoria. O log é `~/Library/Application Support/NeverType/nevertype.log`.

1. **Tudo certo:** dite normalmente. O ícone segue normal e a colagem não parece mais lenta. Se parecer, o cenário 4 da auditoria reabre. O log ganha um `icon → brand` depois de `transcribed in` e nenhuma linha `permissions:` nova.
2. **Permissão tirada durante o ditado:** com as duas concedidas, comece um ditado em mãos livres, desligue a Acessibilidade nos Ajustes e termine. O ícone fica riscado, e o log mostra `permissions: microphone=authorized accessibility=missing` logo antes de `icon → brand.slash`. Ligue de novo sem apertar a tecla: o risco some em cerca de um segundo, e o log mostra `permissions: microphone=authorized accessibility=granted` logo antes de `icon → brand`. Repita uma segunda vez sem reabrir o app (é o que a sonda prende). Se a tecla não terminar o ditado com a Acessibilidade desligada, termine pelo menu, desligando as mãos livres, o que descarta a gravação e também deve deixar o risco. Nesse caminho, a linha da perda sai ao abrir o menu (`rebuildMenu`, `main.swift` 1046), e não logo antes do risco.
3. **Colagem recusada:** dite com o foco onde não dá para digitar. O risco aparece por dois segundos e o ícone volta ao normal.
4. **Modelo indisponível, só se já estiver nesse estado:** o ditado falha, em vez de dar certo como o passo 1 do progresso sugere, porque sem modelo não há transcrição. Em mãos livres, descarte com Esc: o ícone volta riscado, não normal. "Sem Metal" não se produz à mão num Apple Silicon e fica com a prova do Core.
