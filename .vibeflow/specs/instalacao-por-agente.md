# Spec: Instalação conduzida por agente

> Gerado via /vibeflow:gen-spec em 2026-08-29
> A partir de `.vibeflow/prds/instalacao-por-agente.md`

## Objetivo

Alguém que não é o autor manda o link do repositório para o próprio agente, pede
para instalar, e termina ditando.

## Contexto

Ninguém além do autor instalou este projeto. O caminho existe e funciona — mas
funciona na máquina de quem o escreveu, que é onde todo caminho de instalação
funciona.

A decisão que molda esta spec: **quem instala compila na própria máquina.** Isso
não é preguiça de empacotar, é o que apaga a maior parte do trabalho. O
`build-app.sh` já gera um certificado local por máquina, e app compilado
localmente não entra em quarentena — então Gatekeeper, notarização, cask e
processo de release deixam de existir como problema. Atualizar é `git pull` e
recompilar.

O que sobra é o documento. E o documento tem um leitor incomum: um agente de
codificação, que executa em vez de ler, improvisa quando não sabe, e não tem
mãos para clicar nos Ajustes do Sistema.

## Definition of Done

1. **`docs/INSTALL.md` existe e é endereçado ao agente**, não ao humano: ordem
   de passos executáveis, e os **três pontos que exigem a pessoa** marcados como
   tal — Command Line Tools, Microfone, Acessibilidade — cada um com o texto a
   dizer a ela e como confirmar que ela fez.

2. **A fronteira do que o agente conserta sozinho está escrita**, com pelo menos
   estes três do lado proibido: `security list-keychains`, apagar
   `~/Library/Keychains/nevertype-signing.keychain-db`, e qualquer coisa fora do
   repositório e de `~/Library/Application Support/NeverType/`.

3. **`scripts/verificar-instalacao.sh` verifica por estrutura**, e cada
   verificação falha nomeando a ação de saída:
   - `/Applications/NeverType.app` existe e `codesign --verify --strict` passa;
   - o processo está vivo (`pgrep -x NeverType`);
   - o modelo está no destino e é válido pelo **magic em hexadecimal**
     (`6c6d6767`) somado ao piso de tamanho — a mesma regra de
     `fetch-model.sh`, que existe porque proxy de filtragem devolve página HTML
     de erro com nome de modelo.

4. **O script segue o contrato de `scripts-shell.md`**: `set -euo pipefail`,
   `REPO_ROOT` por `BASH_SOURCE`, `info/ok/warn/fail`, idempotente, e espera por
   condição em vez de `sleep` fixo.

5. **Craftsmanship gate.** Nenhuma violação dos Don'ts de `conventions.md`. Em
   particular: **nenhuma conclusão de sucesso por palavra encontrada em log**, e
   nenhum `>/dev/null 2>&1` em comando que pode falhar sem gravar o diagnóstico.

6. **Verificado por efeito, e a verificação é a pessoa.** Alguém que não é o
   autor instala falando só com o agente, e dita uma frase que aparece na tela.
   Cada vez que ela precisou de ajuda humana **fora dos três cliques** é um
   buraco no documento, e conta como falha deste check.

## Escopo

- `docs/INSTALL.md` (novo)
- `scripts/verificar-instalacao.sh` (novo)
- `README.md` — o ponteiro para esse caminho

Três arquivos.

## Anti-escopo

- **Não** notarizar, publicar cask, versionar release ou escrever changelog. A
  compilação local torna os quatro desnecessários; ver Decisão 1.
- **Não** fazer o app baixar o modelo. O binário continua sem código de rede.
- **Não** tentar automatizar concessão de TCC. Não dá, e fingir que dá produz
  instalação que se declara pronta e não funciona — que é o defeito que este
  projeto mais combate.
- **Não** escrever um arquivo de estado que o app atualiza para o script ler.
  Foi considerado e recusado: ver Decisão 3.
- **Não** repetir no INSTALL.md o que os scripts já fazem. O documento aponta
  para `install.sh`, que já recusa cedo o que não tem conserto depois e já
  imprime as instruções de permissão.
- **Não** dar suporte a Intel nem a macOS antigo.

## Decisões técnicas

### 1. Compilar na máquina de quem instala, e é isso que apaga o resto

Cada pessoa gera o próprio certificado no `build-app.sh`. App compilado
localmente não recebe o atributo de quarentena, então o Gatekeeper não aparece —
sem botão direito, sem passeio nos Ajustes de Segurança.

O preço: exige Command Line Tools e `cmake`, e a primeira compilação leva
minutos. É um preço pago uma vez, por uma pessoa que já tem um agente disposto a
esperar.

### 2. O modelo copiado entra por `models/`, nunca direto no destino

Quando a rede bloqueia o download, o `install.sh` já sugere copiar de alguém que
tenha. Mas copiar direto para `~/Library/Application Support/NeverType/models/`
pula toda validação.

O documento manda copiar para `models/` do repositório e rodar
`scripts/fetch-model.sh`, que valida magic e tamanho antes de promover, e apaga
a cópia se ela não ficar válida. **Nada de instrução nova: só usar a que existe
na ordem certa.**

### 3. Sem arquivo de estado; a permissão se prova ditando

A tentação é o app escrever um `estado.json` com microfone e acessibilidade para
o script ler. Recusado por duas razões:

- `estado-consultado.md` existe porque estado de permissão copiado para outro
  lugar envelhece em silêncio. Um arquivo é uma cópia com data de validade
  desconhecida, e o script leria uma verdade de minutos atrás.
- Não resolveria: o que interessa não é "o TCC diz que concedeu", e sim "o
  ditado insere texto". Só a segunda coisa prova.

Então o script verifica **o que dá para verificar de fora** — app instalado,
assinatura, processo, modelo — e diz explicitamente que permissão só se confirma
ditando. O último passo do INSTALL.md é a pessoa falar uma frase.

### 4. A fronteira do agente é por escrito, e larga onde deve ser

| O agente resolve sozinho | O agente para e pergunta |
|---|---|
| `brew install cmake` | Qualquer coisa com `security list-keychains` |
| `xcode-select --install` (e esperar a pessoa) | Apagar o keychain de assinatura |
| Recompilar após falha de build | Escrever fora do repo e do Application Support |
| Repetir download interrompido | Instalar em `/Applications` sem permissão |

A linha do keychain não é paranoia: `list-keychains -s` **substitui a lista
inteira**, e o próprio `build-app.sh` tem um guarda-corpo lá porque errar isso
tira o keychain de login da pessoa e ela perde senhas de Wi-Fi e Safari. Um
agente que improvise nesse comando estraga a máquina de alguém para consertar um
app de ditado.

### 5. O documento fala com o agente, mas o roteiro humano é literal

Os três pontos de intervenção trazem **o texto exato** a ser dito à pessoa, e não
uma instrução para o agente redigir. Motivo: a Acessibilidade é a armadilha nº 1
do projeto — sem ela o app abre, mostra ícone e não reage à tecla, sem erro
nenhum. Uma explicação improvisada que não deixe isso claro produz exatamente a
instalação silenciosamente quebrada que o documento existe para evitar.

## Padrões aplicáveis

- **`scripts-shell.md`** — o script novo segue o esqueleto dos outros seis.
- **`verificacao-estrutural.md`** — magic em hexadecimal com piso de tamanho,
  nunca `grep` de palavra em log. O comentário do `setup-bench.sh` explica por
  que: proxy de filtragem devolve HTML com nome de modelo, e os quatro primeiros
  bytes de um download truncado estão certos.
- **`falha-alta.md`** — toda falha do script nomeia a ação de saída. Aqui isso
  vale dobrado: quem lê é um agente, e agente sem saída definida improvisa.
- **`estado-consultado.md`** — a razão de não existir arquivo de estado
  (Decisão 3).

## Riscos

| Risco | Mitigação |
|---|---|
| O agente conclui "instalado" com a Acessibilidade faltando, e a pessoa acha que o app está quebrado. | DoD 6 é ditar, não instalar. O script diz em voz alta que não verifica permissão. |
| O agente improvisa num comando destrutivo para contornar um erro. | Decisão 4, com a tabela de fronteira dentro do documento e não só nesta spec. |
| A rede corporativa bloqueia o CDN da OpenAI e a instalação para no modelo. | Caminho alternativo por `models/` + `fetch-model.sh` (Decisão 2), que valida a cópia em vez de confiar nela. |
| O documento fica certo hoje e envelhece na primeira mudança de script. | Ele aponta para os scripts em vez de repetir o conteúdo deles; o que ele adiciona é ordem, fronteira e roteiro humano. |
| Testar isto exige uma pessoa e um Mac que não são os do autor. | É o ponto. Sem isso o DoD 6 não fecha, e o item continua sendo o maior risco não testado do projeto. |

## References

- `scripts/install.sh` — já recusa cedo o insalvável e imprime as instruções de
  permissão; o INSTALL.md aponta em vez de repetir
- `scripts/fetch-model.sh` — a validação de magic e tamanho que a Decisão 2 reusa
- `scripts/setup-bench.sh` — o download do CDN da OpenAI, e o comentário que
  explica por que o magic é conferido em hexadecimal
- `docs/armadilhas.md` — o que o agente deve ler antes de improvisar
- `.vibeflow/patterns/scripts-shell.md` — o contrato do script novo
