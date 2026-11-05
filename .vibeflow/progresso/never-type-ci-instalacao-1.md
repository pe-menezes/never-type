# never-type-ci-instalacao, parte 1: progresso

## Feito
* `.github/workflows/install.yml` novo: gatilhos, matriz, 14 passos (os 13 do desenho, com o item 3 em dois passos), job de guarda e o topo com o que prova e o que fica fora.
* `.vibeflow/decisions.md`: entrada `2026-11-05` no topo da lista, em português.
* Blocos exercitados com logs e ferramentas falsas, sempre extraídos do YAML real por `extract.rb`.

## Falta (do PG, pelo briefing)
* Commit do conserto 1, rodada real do workflow com o conserto e reauditoria.

## Provas da primeira rodada (com o resultado visto naquela sessão)
A pasta temporária da sessão fica abaixo como `<tmp>`. Os comandos reais levam o caminho literal.

| Prova | Comando | Resultado |
|---|---|---|
| Vermelho, passo 12 | `SCRATCH_DIR=<tmp> /bin/bash <tmp>/test-model-check.sh <tmp>/naive-block.sh` (bloco ingênuo que aceita qualquer linha `model:`) | 2 passam, 11 falham, antes de o YAML existir |
| YAML carrega | `ruby -ryaml -e 'YAML.load_file(".github/workflows/install.yml")'` | sem erro |
| Sintaxe dos blocos | `/bin/bash <tmp>/extract-all.sh` (`bash -n` em cada bloco) | 5 de 5 |
| Verde, passo 12 | `SCRATCH_DIR=<tmp> /bin/bash <tmp>/test-model-check.sh <tmp>/blocks/model.sh` | 13 de 13: os cinco do contrato e mais oito |
| Verde, passo 12, `LC_ALL=C` | o mesmo com `LC_ALL=C`, porque a regex tem `·` | 13 de 13 |
| Demais blocos | `/bin/bash <tmp>/test-other-blocks.sh` | 30 de 30 |
| Guarda, limite 45 | `GITHUB_REPOSITORY=pe-menezes/never-type QUIET_DAYS_LIMIT=45 /bin/bash -e <tmp>/blocks/guard.sh` com `gh` real | `last commit on main: 19 days ago, limit 45`, exit 0 |
| Guarda, limite 0 | o mesmo com `QUIET_DAYS_LIMIT=0` | `::error::19 days without a commit on main. GitHub turns this schedule off at 60. Any commit on main resets the count.`, exit 1 |
| Prosa | `grep` de travessão, aspas curvas, `rather than`, `instead of`, `whereas` no YAML | nada |
| Perímetro | `git status --short --ignored -- .github .vibeflow scripts Sources docs` | só `decisions.md` e os dois arquivos novos |

Os cinco casos do contrato: linha `Metal` boa passa; `(WARM-UP FAILED)` falha; `CPU (SLOW)` falha; texto de erro falha; processo morto sem linha falha rápido. "Rápido" é provado por um `sleep` falso que conta chamadas (zero), sem comparar relógio.

A cópia do passo 12 troca só `limit=180` por `limit=3`. A do passo 4 troca só `/Applications/NeverType.app` por `$HOME/Applications/NeverType.app`, porque o app dele está instalado nesta máquina. `HOME` e `PATH` apontam para pasta temporária, e nada tocou em `~/Library/Application Support/NeverType` nem em `/Applications`.

## Não rodado
* `actionlint`: não existe na máquina (`command -v` vazio). O critério era "se existir", e não instalei nada. Sintaxe de expressão e de `if` do GitHub só a rodada real confirma.
* Suíte Swift e verificador de tipos: esta parte não muda Swift nem scripts, e o build do worktree exigiria baixar e compilar o whisper.cpp. Não vi placar nenhum dela.
* Workflow num runner, na primeira rodada: quem rodou foi o PG, e o resultado está no relatório da auditoria (`41966080335` e `41966083968`).

## Decisões dentro do desenho
* Rótulos da matriz: `macos-15, system Python` e `macos-26, Homebrew Python`.
* Blocos usam `set -euo pipefail` no início, porque o `run` sem `shell:` no macOS é `bash -e`, sem `pipefail`. O passo 13 usa `set +e` e termina em `exit 0`.
* `brew list --formula` vai para uma variável antes do `grep -q`: um `grep -q` lendo de pipe com `pipefail` pode dar falso negativo, e um `brew` quebrado precisa derrubar o passo (caso `clean-brew-broken`).
* Guarda recusa resposta vazia ou malformada do `gh`. Sem isso, `[ "" -gt 45 ]` erra, o `if` lê como falso e o job fica verde sem medir nada (casos `guard-empty-answer` e `guard-garbage-answer`).
* O regex do passo 12 é a linha inteira, na forma que `main.swift:60-62` grava.

## Fora da parte
* Os fatos dizem "hoje são 20 dias" e o bloco mede 19: o `floor` conta dias inteiros desde o commit. O teste do limite 45 e do 0 não muda.
* Os testes dos blocos ficaram fora do repositório, porque o perímetro não previa arquivo de teste. Se valer guardá-los, vira parte nova. Estão em `<tmp>`, que é temporário: `extract.rb`, `extract-all.sh`, `test-model-check.sh`, `test-other-blocks.sh`, `naive-block.sh`. O briefing dizia `$TMPDIR`, e usei a pasta temporária da sessão, igualmente fora do repositório.
* `docs/INSTALL.md` diz que o tempo do `setup-bench.sh` não foi medido, e os jobs agora dão a ordem de grandeza (6 a 9 min no total). `docs/` está fora desta parte.
* O passo do Python só imprimia a versão, e o `brew uninstall` quebrava em imagem sem a fórmula: os dois saíram no conserto 1, abaixo.

## Conserto 1
Volta 1 de 2, sobre a auditoria em PASS com 7 baixos e a revisão do Codex. Feito em `.github/workflows/install.yml` e na entrada de 2026-11-05 de `decisions.md`.

### O que mudou
* cmake: lista as fórmulas, desinstala só se `grep -qFx cmake` acha, dá `::error::` nomeando o caminho se ainda há cmake, e só então a linha literal do INSTALL.
* Cache: `PIP_NO_CACHE_DIR: "1"` no `env` do job e passo novo `Give Homebrew an empty cache`, antes do primeiro `brew`.
* Passo novo `Update Homebrew`, depois da prova de runner limpo e antes do cmake. `HOMEBREW_NO_AUTO_UPDATE: ""` saiu do job, e o comentário foi junto.
* `Record the Python in use` virou `Prove which Python is in use`, com `EXPECTED_PYTHON` no `env` do passo.
* SDK em duas linhas, mensagem da guarda nova, e os textos pedidos: Metal reportado, guarda como heurística, datas, Python, números, promessas de prazo, rede e o que a imagem traz.

### Provas (rodadas nesta sessão, com o resultado visto)
`<tmp>` é a pasta temporária da sessão, e os scripts desta volta estão em `<tmp>/conserto1`. Os comandos reais levam o caminho literal.

| Prova | Comando | Resultado |
|---|---|---|
| Vermelho, comportamento | `/bin/bash <tmp>/conserto1/test-conserto.sh <tmp>/conserto1/blocks-antes` (blocos extraídos do YAML antes do conserto) | 11 passam, 24 falham |
| Vermelho, estrutura e texto | `ruby <tmp>/conserto1/estrutura.rb .github/workflows/install.yml .vibeflow/decisions.md` antes do conserto | 58 falhas |
| Verde, comportamento | `/bin/bash <tmp>/conserto1/test-conserto.sh <tmp>/conserto1/blocks-depois` | 35 de 35 |
| Verde, estrutura e texto | o mesmo `estrutura.rb` depois do conserto | 70 de 70 |
| YAML carrega | `ruby -ryaml -e 'YAML.load_file(".github/workflows/install.yml")'` | sem erro |
| Sintaxe dos blocos antigos | `/bin/bash <tmp>/extract-all.sh` | 5 de 5 |
| Passo de carga, testes antigos | `SCRATCH_DIR=<tmp> /bin/bash <tmp>/test-model-check.sh <tmp>/blocks/model.sh` | 13 de 13 |
| Demais blocos, testes antigos | `/bin/bash <tmp>/test-other-blocks.sh` | 30 de 30 |

Casos do cmake: fórmula presente; fórmula ausente sem cmake nenhum (quebrava); nome parecido (`cmake-docs`); cmake de fora no `PATH`; fórmula e cmake de fora juntos (passava calado); `brew` falhando na listagem; `uninstall` falhando; `install` falhando. Casos do Python: `system` e `homebrew`, certo e errado; prefixo parecido nos dois; `python3` quebrado; `brew --prefix` quebrado; valor desconhecido na matriz; `system` sem depender de `brew`.

### Sondas do auditor
Rodei `sondas.rb` e `sondas.sh` sobre o YAML novo, com os blocos extraídos em pasta minha. Não editei nenhuma, porque o briefing não autoriza reescrever. As quatro falhas são as que este conserto torna falsas de propósito, e a reauditoria decide a reescrita:

* `sondas.rb`: 1 falha entre as estruturais, `HOMEBREW_NO_AUTO_UPDATE e string vazia`; a variável saiu do job.
* `sondas.sh`: 63 passam, 3 falham. `imagem sem cmake do Homebrew fica vermelha` e `e nao chega a instalar` (o defeito consertado: agora sai 0 e instala) e `outro cmake no PATH sai 0` (agora é `::error::`).

`mutantes.sh` não rodou: com essas sondas já vermelhas, todo mutante daria "morto" sem provar nada. Depende da reescrita pela reauditoria.

### Conferido agora
* PR #15: `createdAt 2026-09-18T01:36:06Z`, `mergedAt 2026-09-22T00:02:20Z` (`gh pr view 15`). O commit do rename vem do relatório da auditoria, sem nova consulta.
* `build-app.sh:123` é o `openssl req`, e `build-app.sh:221` fixa `306c88f4d1286aec1bf96e544632897886af5501`.
* `sys.base_prefix` nesta máquina: `/opt/homebrew/bin/python3` dá `/opt/homebrew/opt/python@3.14/Frameworks/...`, que começa com o prefixo esperado. `/usr/bin/python3` dá `/Applications/Xcode.app/Contents/Developer/Library/Frameworks/...`, com o `xcode-select` aqui no Xcode. Por isso a prova roda depois da seleção das Command Line Tools.

### Não provado sem rodada real
* O caminho `/Library/Developer/CommandLineTools/` do `base_prefix` no runner: é a expectativa do briefing, e esta máquina não o mostra, por estar no Xcode. Se a rodada real der outro caminho, o job de `macos-15` fica vermelho no passo novo.
* `brew update`, `HOMEBREW_CACHE` e `PIP_NO_CACHE_DIR` de verdade: não rodei `brew` nem `pip`. Sobre eles só há prova de ordem e de texto.
* A data de 04/11/2026 do e-mail veio do briefing, sem conferência: a API não expõe, e não abri a caixa de e-mail.

### Fora deste conserto
* `docs/INSTALL.md` dizer que o tempo não foi medido: `docs/` não é desta parte.
* Resumo em job cancelado: segue sem rodada real.
