# never-type-ci-instalacao, parte 1: progresso

## Feito
* `.github/workflows/install.yml` novo: gatilhos, matriz, 14 passos (os 13 do desenho, com o item 3 em dois passos), job de guarda e o topo com o que prova e o que fica fora.
* `.vibeflow/decisions.md`: entrada `2026-11-05` no topo da lista, em português.
* Blocos exercitados com logs e ferramentas falsas, sempre extraídos do YAML real por `extract.rb`.

## Falta (do PG, pelo briefing)
* Rodar o workflow de verdade e a sabotagem. Nada aqui rodou num runner.
* Commit.

## Provas (rodadas nesta sessão, com o resultado visto)
A pasta temporária é `/private/tmp/claude-501/-Users-pedromenezess-Library-Mobile-Documents-iCloud-md-obsidian-Documents-Obsidian-Vault/d82bcdb9-6cbb-4721-9ee5-ade7373bb568/scratchpad`, abaixo `<tmp>`. Os comandos reais levam o caminho literal.

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
* Workflow num runner: é do PG.

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
* O passo do Python só imprime a versão, como pede o desenho. Se a imagem deixar de ter o 3.9.6 em `/usr/bin/python3`, o job segue e testa outra versão sem falhar.
* `brew uninstall --formula cmake` falha se a imagem deixar de trazer o cmake pelo Homebrew: seria um aviso de falha sem quebra real da instalação. O comentário do passo já diz isso.
