# Reauditoria 1, never-type-ci-instalacao, parte 1

Reauditado: o diff do conserto 1, base `41767ab`, HEAD `63505ef`, branch `ci/install-from-scratch` (PR #21). Medido em 05/11/2026, terminado às 02:0x (horário de Brasília). O conserto ficou no escopo dos achados, então não refiz a auditoria inteira.

## Veredito: PASS

Nenhum defeito e nenhum buraco em código de risco. Todos os achados pedidos estão fechados, salvo uma parte do B7 que só existe depois do merge. Ficam quatro baixos novos, de texto e de registro, e dois baixos antigos que viram tarefa. Nenhum segura o merge pela régua.

As quatro perguntas que o executor não pôde provar têm resposta na rodada real, e a rodada do conserto ficou verde nos dois jobs, com a sabotagem vermelha pelo motivo certo.

## Achados pedidos

| Achado | Estado | Prova |
|---|---|---|
| Codex, defeito: `brew uninstall` quebra em imagem sem a fórmula | Fechado | Sonda `imagem sem a formula e sem cmake fica verde`, chamadas exatas `list, install`. Mutantes `desinstala sem olhar a lista`, `nunca desinstala` e `nome parecido conta` mortos. Real: `Uninstalling .../cmake/4.4.4`, depois `Pouring cmake--4.4.5`, nos dois jobs |
| Codex, buraco: cmake de fora do Homebrew passa calado | Fechado | Sondas `cmake de fora no PATH fica vermelho`, com o caminho na mensagem e sem `install`, e `formula e cmake de fora juntos`. Mutante `cmake de fora nao para` morto |
| Codex, buraco: "sem cache nenhum" | Fechado | `HOMEBREW_CACHE: /Users/runner/work/_temp/homebrew-cache` no env de todo passo depois do seu, nos dois jobs, e passo antes do primeiro `brew` (índice 1 contra 4). Sem `HOMEBREW_CACHE is not writable`, o aviso de `brew.sh:513`. `PIP_NO_CACHE_DIR: 1` em todo passo. Pip real sem rede: desliga em 21.2.4 e 26.2.1, com controle. Real: zero `Already downloaded` e zero `Using cached`; o limite está abaixo |
| Codex, buraco: auto-update pode falhar calado | Fechado | Passo só com `brew update`, entre limpeza e cmake, sem `continue-on-error`. Mutante `falha engolida` morto. Código do Homebrew: falha de `git fetch` e de API chega a `update-report.rb:238`, `Homebrew.failed = true`. Real: `Outdated Formulae` lista `cmake`, e sai `cmake 4.4.5` e `ggml 0.29.0`; o passo não exercitou falha real |
| Codex, buraco: origem do Python só impressa | Fechado | Real: `system Python at /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9` e `homebrew Python at /opt/homebrew/opt/python@3.15/Frameworks/Python.framework/Versions/3.15`. Sondas com Python falso, certo, errado, parecido, vazio e matriz desconhecida. Com Python de verdade: por link e por venv, `base_prefix` vê a origem; `/usr/bin/python3` fica vermelho nesta máquina, que está no Xcode, o que confirma o comentário sobre a ordem. Seis mutantes mortos |
| Codex: Metal como o que o app reporta | Fechado, só texto, por decisão | Topo, comentário do passo e decisão dizem o limite. Regex intacto. Repeti a sonda: exit 134, `failed to initialize MTL0 backend`, zero linhas `model:`. `Transcriber.swift:193-198` e o commit `306c88f` (`build-app.sh:221`) conferem |
| Codex e B4: guarda como heurística, inferência escrita como inferência | Fechado | `install.yml:361-365` e decisão. Mensagem nova no runner real: `19 days without a commit on main. GitHub turns a quiet public repository's schedule off at 60 days. Any commit on main resets this count.` |
| Codex: `echo` do SDK mascara falha | Fechado | Sonda devolve o código 9 do `xcrun`, mutante morto. Real: `SDK 15.5` e `SDK 26.5` |
| Codex e B7: "at most 7 days", "the tree the PR already proved" | Fechado | As frases saíram do YAML e da decisão (`estrutura.rb`). Texto novo sem prazo, e `push` justificado só pelo custo. A ressalva de rodada perdida entrou em `install.yml:367-369` |
| B1: data | Fechado | `gh api`: `dfc545ca32`, committer `2026-09-12T16:21:44Z`, author `2026-08-22T04:02:19Z`. PR #15: `2026-09-18T01:36:06Z` e `2026-09-22T00:02:20Z`. Ver N3 |
| B2: máquina de quem desenvolve | Fechado | A frase saiu. Ver N1 sobre a palavra que entrou |
| B3: resto da imagem, cópia do INSTALL | Fechado | Frase igual no topo e no resumo (sonda `item do resumo esta no topo`, cinco de cinco). `build-app.sh:123` é o `openssl req`. Comentário em `install.yml:98-99`. A linha do cmake está igual em `docs/INSTALL.md:82` |
| B5: e-mail depende da conta | Fechado no texto | `decisions.md:48-49`. Que o e-mail chegou não é conferível daqui: a API não expõe e não abri caixa de e-mail. Ver N2 |
| B6: rede também deixa vermelho | Fechado | `install.yml:31-33` e decisão |
| B7, números | Fechado | "about 6 to 9 min" e "about 15 s". A rodada nova deu 8 min 55 s e 8 min 36 s, dentro da faixa |
| B7, progresso público | Fechado | Sem `/private/tmp`, `/Users/...` nem e-mail no YAML, na decisão, no progresso e na auditoria (`grep`). A frase vencida saiu |
| B7, caminhos sem rodada real | Aberto, baixo, tarefa | `schedule` e `workflow_dispatch` só existem depois do merge. Resumo em job cancelado segue sem rodada real, e o progresso declara. Um `gh workflow run install.yml` logo depois do merge fecha os dois primeiros |

**O limite da prova de cache.** A rodada antiga também teve zero `Already downloaded` e zero `Using cached` (`real-21.txt`): a imagem de hoje não guarda esses arquivos. A rodada real prova que a configuração vale e não atrapalha. Que ela protege contra uma imagem com cache cheio se apoia no código (`brew.sh:51`, parser do pip), sem caso real.

## Saída de `HOMEBREW_NO_AUTO_UPDATE: ""`

Nada mais dependia dela.

* Sem referência em `run` nem em `env` (sonda), e nenhum script a lê (`grep` no repositório: só comentário, decisão, progresso e auditoria).
* A variável da imagem volta a valer para os `brew` seguintes, e por isso `brew install cmake` e o `brew install whisper.cpp` de `setup-bench.sh:50` não atualizam sozinhos: zero `Auto-updat` no log novo, contra dois jobs com `Auto-updated Homebrew!` no antigo. Eles usam o que o `brew update` trouxe minutos antes.
* O resultado é o mesmo da rodada antiga nos dois jobs: `cmake 4.4.5`, `ggml 0.29.0`, `whisper.cpp 1.9.5`.
* O log novo diz `Updated 1 tap (hashicorp/tap)`, sem `homebrew/core`, contra `Updated 2 taps (homebrew/core and homebrew/cask)` no antigo. Quem lê pode achar que a fórmula não atualizou, e atualizou: a mesma saída lista `cmake` como desatualizada e instala 4.4.5 sobre o 4.4.4 da imagem. Inferência minha para a frase: com o cache vazio não há API anterior para comparar. Não testei essa causa.

## Sondas velhas

Rodadas sem edição sobre o YAML novo: `sondas.rb` 24 de 25, `sondas.sh` 63 de 66, os números do executor. As quatro são falsas pelo fato.

| Sonda | Por que é falsa | Reescrita |
|---|---|---|
| `HOMEBREW_NO_AUTO_UPDATE e string vazia` | A variável saiu de propósito | Mesmo contrato, fórmula de hoje e sem seguir sem ela: passo só com `brew update`, na ordem, nada engole falha, ninguém redefine a variável |
| `imagem sem cmake do Homebrew fica vermelha` e `e nao chega a instalar` | Prendiam o defeito consertado | `fica verde`, com as chamadas exatas `list, install` |
| `outro cmake no PATH sai 0` | Agora é `::error::`, como o Codex pediu | `fica vermelho`, com o caminho na mensagem e sem `install` |

**O que o executor não listou.** Outras duas passavam, mas tinham ficado vazias: `cmake normal sai 0` e `cmake normal chama a linha do INSTALL`. O `brew` falso delas não lista nada, então o `uninstall` deixou de ser exercitado. Passavam sem provar o caminho normal. Reescrevi com um falso que lista, recusa `uninstall` sem keg e só cria o cmake no `install`. O mutante velho `instala mesmo com cmake no PATH` ficou equivalente em comportamento, porque o `::error::` vem antes. Ele morre agora pela sonda da linha literal, e somei os que atacam a lógica nova.

Força final: `sondas.rb` de 25 para 37, `sondas.sh` de 66 para 111, mutantes de 7 para 24, todos mortos. Tudo fora do repositório, em cópia.

## Rodadas reais

Lidas uma vez cada. Às 01:4x estavam em andamento, com os passos novos em `success` até o cmake; o log foi lido às 02:00, com as rodadas terminadas. `gh pr checks` deu o estado final.

* **41969293402** (PR #21, `63505ef`): os dois jobs de instalação em `pass`, guarda `skipping`, `ci.yml` em `pass` nos três jobs. `Metal · load 19401 ms · warm-up 21016 ms` e `Metal · load 16644 ms · warm-up 15111 ms`. `torch-2.8.0` no system, `torch-2.15.0` no Homebrew.
* **41969294555** (PR #22, `938a1d6`): `fail` nos três jobs, cada um pelo motivo certo. Os dois de instalação em `Set up the models`, com `Homebrew's test files are missing from /opt/homebrew/share/whisper-cpp`, sem os passos seguintes. A guarda com `last commit on main: 19 days ago, limit 0` e a mensagem nova. `Summarize` rodou nos dois, sem `##[error]`. `ci.yml` em `pass`.

Os passos novos rodaram antes da quebra na sabotagem, igual ao PR #21: a sabotagem segue vermelha por causa da fórmula, sem o conserto mascarar.

## Baixos novos

### N1. "Homebrew's current python3" não é o atual

`install.yml:82` e `decisions.md` dizem que o job usa o `python3` atual do Homebrew. É o que a imagem traz. No macos-26, `brew update` lista `python@3.15` em `Outdated Formulae`, e o job não atualiza. A versão provada foi 3.15.1 nesta rodada e 3.15.2 na anterior (`real-21.txt:137`), então ela muda por imagem. A frase veio do briefing do conserto. `3.15.x` continua certo, e o `base_prefix` prova a origem, não a idade. Conserto de uma palavra: "the python3 Homebrew has on this image".

### N2. Progresso vencido em duas linhas

* `progresso/...-1.md:91` diz que a data do e-mail é 04/11/2026, e `decisions.md:49` diz 05/11/2026. A decisão é a certa quanto à rodada: a sabotagem nasceu em `2026-11-05T04:09:57Z`, 01:09 de 05/11 no Rio. Por isso `estrutura.rb` do executor agora dá 69 de 70, na frase `decision says [04/11/2026]`: o texto mudou depois da sessão dele. A sonda é de estado, e o fato novo está certo.
* A seção "Não provado sem rodada real" e a linha de "Falta" já têm resposta nesta reauditoria.

### N3. Dois fusos na mesma frase

`decisions.md` dá o PR #15 como aberto em 18/09, que é a data em UTC (no Rio, 17/09 às 22:36), e a mesclagem em "21/09 no Rio". "A contribuidora achou em 6 dias" é contagem de calendário em UTC; o intervalo real é de 5,4 dias. Os 9 dias da quebra seguem certos. Veio assim do briefing do conserto, e não muda nenhuma conclusão.

### N4. O commit do conserto tocou no relatório da auditoria

O briefing do conserto dizia que o relatório não era do executor, e `63505ef` muda a linha 80 dele, trocando o caminho local por "os da pasta temporária da sessão". O progresso não cita essa mudança, e não dá para saber pelo git quem a fez: há um commit só. É uma redação de caminho para o repositório público e não altera achado nem veredito. Fica o registro. Fora dessa linha, o perímetro bate: só a entrada de 2026-11-05 na decisão.

### Baixo antigo, vira tarefa

As provas de comportamento dos blocos seguem só na pasta temporária, como o briefing mandou. O executor já tinha apontado que guardá-las é parte nova. Nada no repositório exercita esses blocos entre rodadas reais. Não é código de risco.

## Fora do repositório, para o PG

`.claude/threads/never-type-ci-instalacao.md:10`, no vault, ainda diz `22/08 a 21/09/2026`.

## Sondas e comandos

Nenhuma sonda vai para a suíte. O briefing as manda para fora do repositório, e o repositório não tem teste de workflow. Abaixo, `<aud>` é a pasta `auditoria/` e `<re>` é a pasta `reauditoria/`, ambas na pasta temporária da sessão, e `<wt>` é o worktree. Os comandos reais levam o caminho literal.

| Comando | Resultado |
|---|---|
| `ruby <aud>/sondas.rb <wt>/.github/workflows/install.yml <wt>/Sources/NeverType/main.swift <re>/velhas/blocks` | 24 de 25; 16 blocos |
| `/bin/bash <re>/sondas-original.sh <re>/velhas/blocks` (cópia idêntica) | 63 de 66 |
| `ruby <re>/sondas.rb <wt>/.github/workflows/install.yml <wt>/Sources/NeverType/main.swift <re>/blocks` | 37 de 37 |
| `/bin/bash <re>/sondas.sh <re>/blocks` | 111 de 111 |
| `/bin/bash <re>/mutantes.sh <re>/blocks` | 24 mutantes em cópias dos blocos, 24 mortos |
| `/bin/bash <re>/sonda-pip.sh /usr/bin/python3 /opt/homebrew/bin/python3` | 4 de 4 |
| `/bin/bash <scratch>/conserto1/test-conserto.sh <re>/conserto-blocks` | 35 de 35 |
| `ruby <scratch>/conserto1/estrutura.rb <wt>/.github/workflows/install.yml <wt>/.vibeflow/decisions.md` | 69 de 70, ver N2 |
| `SCRATCH_DIR=<re>/exec /bin/bash <re>/exec/test-model-check.sh <re>/exec/blocks/model.sh` | 13 de 13 |
| `/bin/bash <re>/exec/test-other-blocks.sh` | 30 de 30 |
| `ruby -ryaml -e 'YAML.load_file(...)'` | YAML carrega |
| `<aud>/metal-false-green <never-type>/models/ggml-large-v3-turbo-q5_0.bin --no-metal-lib` | exit 134, zero linhas `model:` |
| `gh run view 41969293402 --json ...`, `gh run view 41969294555 --json ...` | Em andamento na leitura |
| `gh run view 41969293402 --log`, `gh run view 41969294555 --log`, lidos por `python3 -I <re>/ler-log.py` | Trechos acima |
| `gh pr checks 21`, `gh pr checks 22` | PR #21 em `pass`, PR #22 em `fail` nos três do workflow |
| `gh api repos/Homebrew/homebrew-core/commits/dfc545ca32`, `gh pr view 15` | Datas de B1 |

**Não rodado.** A suíte Swift local: o diff não toca Swift nem scripts, e o build exigiria baixar e compilar o whisper.cpp. O placar dela é o `ci.yml` real, em `pass` nos três jobs do PR #21. `actionlint` não existe na máquina (progresso), e a rodada real cobre a sintaxe.

Sabotagem só em cópias dos blocos, em `<re>`, sem backup porque o worktree não foi tocado: só este relatório é arquivo novo nele (`git status --short`). Não toquei em `/Applications`, em `~/Library/Application Support/NeverType` nem no keychain, não rodei `brew` de verdade nem baixei modelo. A `metal-false-green` leu o modelo já presente no checkout `never-type`. `gh` só em leitura.
