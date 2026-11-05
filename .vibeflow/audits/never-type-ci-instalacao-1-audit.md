# Auditoria never-type-ci-instalacao, parte 1

Auditado: `.github/workflows/install.yml` e a entrada de 2026-11-05 em `.vibeflow/decisions.md`, branch `ci/install-from-scratch`, HEAD `fd45ff7`, base `6179eee` (PR #21). Medido em 05/11/2026, terminado às 01:31 (horário de Brasília).

## Veredito: PASS

Nenhum defeito e nenhum buraco em código de risco. Ficam sete achados baixos, que viram tarefa ou conserto de texto, e nenhum deles segura o merge pela régua (dev-remoto, princípio 6). O B1 e o B2 são frases falsas num arquivo público, e são os dois que eu consertaria antes do merge, porque custam uma linha cada.

### Resposta à pergunta central

**Existe caminho em que o workflow fica verde sem o efeito que diz provar?** Nenhum foi achado nos passos que julgam.

* A hipótese mais forte era a linha `Metal ·`. `usesMetal` vem da lista de devices do ggml (`Transcriber.swift:193-198`), e essa lista não diz que backend o whisper escolheu. Testei o caminho com o código fixado (`306c88f`) e a biblioteca Metal recusada: o whisper loga `failed to initialize MTL0 backend` e o processo aborta com exit 134 (`pre-allocated tensor (leaf_0) in a buffer (MTL0)`), antes de qualquer linha `model:`. Esse caminho fica vermelho, pelo `exited before writing a model line`. A hipótese caiu. O motivo é um comportamento do whisper fixado, e trocar o commit do whisper reabre a pergunta.
* Os caminhos verdes de menor peso, que são cobertura incompleta, estão em B3.

**Existe caminho vermelho sem quebra da instalação?** Sim, e quase todos são escolha declarada.

| Causa | Declarada? |
|---|---|
| Imagem deixa de trazer cmake pelo Homebrew | Sim, `install.yml:154-157` |
| Imagem passa a trazer whisper-cli, ou sobra de execução anterior | Sim, `install.yml:119-122` |
| `main` passa de 45 dias sem commit | Sim, `install.yml:292-297`, com mensagem própria |
| Falha de rede que passe do que cada ferramenta tenta sozinha (`git clone` e `git fetch` não tentam de novo) | Não, ver B6 |
| API do GitHub fora do ar na guarda | Não; falha ruidosa, custo de um e-mail |

**O que o arquivo diz cobrir bate com os passos?** Bate no que julga. O topo, o resumo e a decisão descrevem os mesmos limites, e os cinco itens do resumo estão frase por frase no topo (sonda). As frases erradas são de fato e número, em B1 e B2.

## Achados

Todos com severidade **baixo**. Nenhum defeito, nenhum buraco em código de risco.

### B1. A data do início da quebra está errada: foi 12/09, não 22/08

`install.yml:7` e `decisions.md:17` dizem que a instalação quebrou de 22/08 a 21/09/2026. O rename só entrou no homebrew-core em 12/09.

* `gh api 'repos/Homebrew/homebrew-core/commits?path=Formula/w/whisper-cpp.rb&per_page=6'`: `dfc545ca32 2026-09-12T16:21:44Z whisper-cpp: rename to whisper.cpp`, e o anterior é `b8e460609f 2026-08-04 update 1.9.2 bottle`.
* `gh api repos/Homebrew/homebrew-core/commits/76b9768062`: `author date` 2026-08-22T04:02:44Z, `committer date` 2026-09-12T16:21:45Z. O 22/08 é a data de autoria do commit, que passou três semanas sem estar na fórmula de ninguém.

Quebrada, portanto, por cerca de 9 dias, não 30. O fim está certo: PR #15 mesclado em 2026-09-22T00:02Z, que é 21/09 no Rio. O ponteiro `.claude/threads/never-type-ci-instalacao.md:10` traz o mesmo erro. Inferência minha: o começo vale para quem instalou depois do commit de 12/09; não testei a propagação da API do Homebrew hora a hora.

### B2. "A máquina de quem desenvolve" tem outro Python

`install.yml:70` diz `The developer's machine: Homebrew Python 3.15.x with torch 2.15.0`, e `decisions.md` repete "a máquina de quem desenvolve". Nesta máquina, medido agora: `/opt/homebrew/bin/python3 --version` dá 3.14.7, e o venv de `~/Projects/apps/never-type/.cache` é Python 3.14.7 com `torch-2.13.0` e `numpy-2.5.2`. O 3.15.x e o torch 2.15.0 são do runner. O job continua útil, porque testa o Python mais novo do Homebrew. A frase é que precisa dizer isso.

### B3. O que fica fora não lista o resto da imagem, e o workflow roda uma cópia do INSTALL

Dois caminhos verdes que nenhum dos três textos declara.

* O topo e o resumo citam só Command Line Tools, Homebrew, git e Xcode, e o comentário da matriz chama o job de macos-15 de `The clean Mac`. A imagem traz muito mais no `PATH`: 18 a 21 fórmulas desatualizadas instaladas (`You have 18 outdated formulae`, sonda 3), com `/opt/homebrew/bin` na frente. Um script que passe a depender de uma ferramenta que só a imagem tem fica verde aqui e quebra no Mac limpo. Hoje o único candidato que achei é `openssl req` em `build-app.sh:123`, sem caminho absoluto, ao lado do `/usr/bin/openssl` da linha 130. Qual `openssl` responde no runner **não foi medido**: o log não imprime.
* `install.yml:161` copia a linha do `docs/INSTALL.md`, e os demais passos seguem a ordem dele por construção. Um INSTALL que mude ou quebre sozinho fica verde: `docs/INSTALL.md` e o espelho em português nem estão no filtro de `paths`. O topo diz `in the order of docs/INSTALL.md` como fato de hoje, sem conferência.

### B4. Duas afirmações sobre o GitHub são inferência escrita como fato

Conferido na fonte (`docs.github.com`, lido por `curl` nesta sessão):

| Afirmação | Fonte |
|---|---|
| Agendamento desliga aos 60 dias sem atividade em repositório público | Confirmada, palavra por palavra, em "Disabling and enabling a workflow" |
| Aviso vai a quem criou o workflow ou mudou o cron | Confirmada em "Notifications for workflow runs" |
| Workflow reabilitado avisa quem reabilitou | Confirmada na mesma página |
| Fora da hora cheia atrasa menos | Confirmada em "Events that trigger workflows" |
| **Rodada agendada não conta como atividade** | **A doc não diz.** "Activity" não é definida. Inferência |
| **Qualquer commit na `main` zera a contagem** | **A doc não diz.** Inferência razoável, mas é a frase da mensagem de erro |

`install.yml:292-294` põe a primeira logo depois do `(docs: ...)`, e quem lê entende que a doc diz. A guarda continua certa nos dois casos, porque medir só commit erra para o lado seguro: outra atividade só antecipa um aviso. Conserto: "(inference: the docs do not define activity)".

### B5. O aviso depende de uma configuração da conta que ninguém conferiu

`install.yml:32-33` diz que quem muda o cron `starts receiving the failure e-mail`. A doc condiciona: `If you enable email or web notifications for GitHub Actions`. Toda a razão de existir do workflow é avisar sem ninguém olhar. Se a conta do Pedro estiver com o aviso de Actions desligado, uma quebra fica vermelha em silêncio e a guarda não salva. A API não expõe essa configuração, então só ele confere, em Settings, Notifications, Actions. Passo dele, de um minuto.

### B6. Falha de rede vira vermelho e e-mail sem quebra

Retry explícito só existe no `curl` dos checkpoints (`--retry 5`, `setup-bench.sh:224`). O `git clone` do whisper.cpp (`build-app.sh:230`), o `git fetch` dos assets (`model-artifacts.sh:45`) e o `curl` do conversor (`setup-bench.sh:197`) tentam uma vez; `brew` e `pip` ficam no padrão de cada um, que não medi. Nenhum texto do arquivo diz que um vermelho isolado pode ser rede. Custo baixo, e uma rodada manual tira a dúvida. A conferir na primeira falha real.

### B7. Miudezas de texto e de prova

* **Números.** `install.yml:77` diz `6 min 09 s to 8 min 59 s`; pelos logs das rodadas de instalação inteira (`duracoes.py`) são 6 min 14 s a 9 min 08 s, e pela API 6 min 15 s a 9 min 10 s. `install.yml:169` diz `14 to 15 s`; as três medições são 13,9 s, 15,3 s e 17,0 s.
* **Duas promessas sem a ressalva da doc.** `at most 7 days later` (`install.yml:38`) e `two warnings before day 60` (`:297`) valem se nenhuma rodada se perder, e a doc avisa que `some queued jobs may be dropped`. Com uma rodada perdida, sobra um aviso (sonda abaixo). E `it is the tree the PR already proved` (`:39-40`) não vale para um PR de Swift, como a frase anterior acabou de dizer.
* **Caminhos ainda sem rodada real.** `schedule` e `workflow_dispatch` só existem depois do merge: a doc pede o arquivo na branch padrão. A guarda rodou real só com `if: true` no PR #22. O resumo em job cancelado foi só local e pela doc de `always()`: `gh run list` tem duas rodadas e nenhuma cancelada. Um `gh workflow run install.yml` logo depois do merge fecha os dois primeiros.
* **Arquivo de progresso.** `.vibeflow/progresso/never-type-ci-instalacao-1.md` vai para o repositório público com caminhos locais do Pedro (`/private/tmp/claude-501/-Users-pedromenezess-...-Obsidian-Vault/...`) e com `Nada aqui rodou num runner`, que já não é verdade. Sem credencial. O `never-type-permissoes-1.md` já é precedente de arquivo versionado nessa pasta.

## Pontos que o briefing pediu

| Ponto | Resultado | Prova |
|---|---|---|
| `HOMEBREW_NO_AUTO_UPDATE: ""` e `brew config` | Vazio equivale a ausente. Com `=1`, o `brew config` lista `HOMEBREW_NO_AUTO_UPDATE: set`; com `=` vazio, a linha some. `auto-update.sh:21` testa `-z`. No runner real, `Auto-updated Homebrew!` nos dois jobs e ggml 0.29.0 | `brew config` local nos dois valores (Homebrew 7.0.12); `log.txt` mostra `set` com o valor do runner; `real-21.txt` |
| Heredoc indentado | No runner real, corpo e `EOF` chegam na coluna 0; nada indentado, cinco itens, cerca fechada | Log da 41966080335 e sondas `resumo` |
| `$GITHUB_PATH` | Vale do passo seguinte em diante. `Record the Python` mostra `/Users/runner/work/_temp/system-python/python3` e 3.9.6; `torch 2.8.0` confirma que o `setup-bench.sh` usou esse Python. No macos-26, `/opt/homebrew/bin/python3`, 3.15.2, torch 2.15.0 | Log da 41966080335 e sondas `python` |
| `·` em locale `C` | Passa nos três locales, com os mesmos veredictos; bytes `C2 B7` iguais no YAML e no `main.swift`; o log inteiro do runner, com `⌘` e `→`, é lido certo | Sondas `model[...]` e `log real` |
| Resumo em job cancelado ou sem log | Sai 0 sem a pasta do app, com log ilegível e sem `GITHUB_STEP_SUMMARY`. Em falha real, PR #22: `Summarize` em `success` nos dois jobs | Sondas `resumo` e `gh run view 41966083968` |
| Cron | `17 9 * * 4` é quinta, 09:17 UTC, 06:17 em São Paulo. 2026-11-05 é quinta | `sondas.rb` |
| `if` da guarda | `skipped` no PR #21, sem passo nenhum; roda com `if: true` no PR #22 | `gh run view` das duas |
| 45 dias | Passa em 45, falha em 46. Dois avisos antes do dia 60 em todo horário de commit na semana (10.080 minutos varridos); um, se uma rodada se perder | Sonda `dois avisos`; mutantes `-ge` e `-lt` mortos |
| `GH_TOKEN` e injeção | Sem `${{ }}` em nenhum `run`. Sem `secrets`. Token só na env do job de guarda, que não usa action de terceiro. `GITHUB_TOKEN Permissions: Contents: read, Metadata: read` no log. `actions/checkout` no sha de `v4.2.2`, conferido, sem persistir credencial | `sondas.rb`, log do job 127043297087, `gh api` da tag |
| Conversas do PR | `nenhuma conversa sem resolver em #21` | `conversas-pr.py`, rodado no início da auditoria |

## Rodadas reais

* **41966080335** (PR #21, o workflow como está): `success`. macos-15 em 7 min 53 s, `nevertype: model: Metal · load 19545 ms · warm-up 23277 ms`. macos-26 em 6 min 41 s, `Metal · load 13266 ms · warm-up 11771 ms`. Guarda `skipped`. `ci.yml` verde nos três jobs (`gh pr checks 21`).
* **41966083968** (PR #22, sabotagem): `failure` nos três jobs, cada um pelo motivo certo. Os dois de instalação em `Set up the models`, com `Homebrew's test files are missing from /opt/homebrew/share/whisper-cpp`, o erro exato do PR #15, e os passos seguintes `skipped`. A guarda com `19 days without a commit on main`, depois de medir de verdade pelo `gh` real, sem erro de autenticação.

## Números conferidos

Batem com os logs das sondas e da rodada real: Swift 6.1.2 e SDK 15.5 (macos-15), Swift 6.3.3 e SDK 26.5 (macos-26); Python 3.9.6 das Command Line Tools, torch 2.8.0, numpy 2.0.2; tamanhos 574041195, 539212467 e 190085487, iguais com os dois Pythons; tap de 8 a 10 dias; ggml 0.27.0 contra 0.29.0; whisper.cpp 1.9.5 com `oldname` `whisper-cpp`; `share/whisper.cpp` existe e `share/whisper-cpp` não; 37 s e 30 s até a linha; cmake em 17 s; `Apple Paravirtual device`; `microphone=notDetermined accessibility=missing`; 1542 + 1457 + 461 MB por job, 6,9 GB por rodada; último commit na `main` em 2026-10-16; contribuidora do PR #15 (`lorenacoimbra-dev`). Os que não batem estão em B1, B2 e B7.

## Sondas

Ficam em `$TMPDIR`, como o briefing manda, e nenhuma vai para a suíte: não há achado que peça teste no repositório. Pasta: `<scratch>/auditoria/`, abaixo `<aud>`. Os comandos reais levam o caminho literal.

| Comando | Resultado |
|---|---|
| `ruby <aud>/sondas.rb <worktree>/.github/workflows/install.yml <worktree>/Sources/NeverType/main.swift <aud>/blocks` | 25 de 25; 14 blocos extraídos |
| `/bin/bash <aud>/sondas.sh <aud>/blocks` | 66 de 66 |
| `/bin/bash <aud>/mutantes.sh <aud>/blocks` | 7 mutantes em cópias dos blocos, 7 mortos |
| `SCRATCH_DIR=<aud>/exec /bin/bash <aud>/exec/test-model-check.sh <aud>/exec/blocks/model.sh` | 13 de 13, como o executor declarou |
| `/bin/bash <aud>/exec/test-other-blocks.sh` | 30 de 30, como o executor declarou |
| `<aud>/metal-false-green <never-type>/models/ggml-large-v3-turbo-q5_0.bin` | Controle: `using MTL0 backend`, `Metal · load 10037 ms · warm-up 505 ms`, exit 0 |
| O mesmo com `--no-metal-lib` | `failed to initialize MTL0 backend`, abort, exit 134, sem linha `model:` |
| `python3 <aud>/duracoes.py <logs>` | Durações usadas em B7 |

As duas primeiras versões de `sondas.rb` e `sondas.sh` acusaram falha por erro da própria sonda (`scripts/update.sh` citado no resumo contado como chamado; `PATH=x command -v` não usa o `PATH` temporário no bash 3.2; encoding do Ruby). Corrigi a sonda, e os números acima são da rodada final.

Sabotagem: só em cópias dos blocos, dentro de `<aud>`. O worktree não foi alterado, e só este relatório é arquivo novo nele (`git status --short`). Não toquei em `/Applications`, em `~/Library/Application Support/NeverType` nem no keychain, e não rodei `brew install`, `brew uninstall`, `setup-bench.sh` nem `install.sh`. A `metal-false-green` leu o modelo do checkout `never-type` e as libs de `vendor/whisper`, só leitura.
