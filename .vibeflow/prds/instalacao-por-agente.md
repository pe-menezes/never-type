# PRD: Instalação conduzida por agente

> Gerado via /vibeflow:discover em 2026-08-29

## Problema

Ninguém além do autor instalou o FalaFlow. O caminho existe — clonar,
`build-app.sh`, `install.sh`, conceder permissões, buscar o modelo — mas nunca
foi percorrido por outra pessoa, então cada suposição dele é um abandono em
potencial na primeira tentativa.

E as duas rotas óbvias de distribuição custam caro para o retorno: notarizar
exige Developer ID e reconceder permissões; cask do Homebrew exige processo de
release versionado a cada mudança. Para um app usado por um punhado de pessoas,
as duas são cerimônia.

## Público

Colegas do autor que usam Claude Code. A distribuição é uma frase: *"manda o
link do repositório pro teu Claude e pede pra instalar"*.

Isso exclui de propósito quem não usa agente. É uma troca aceita: o alcance
menor compra a eliminação de toda a cadeia de notarização e empacotamento.

## Solução proposta

Um `docs/INSTALL.md` escrito para ser executado por um agente de codificação,
não lido por humano. Ele conduz clone, dependências, compilação, instalação,
modelo e permissões — e termina numa verificação que prova que o ditado
funciona.

**O que essa escolha apaga:** compilando na própria máquina, cada pessoa gera o
próprio certificado local, que é como o `build-app.sh` já funciona. App
compilado localmente não entra em quarentena, então o Gatekeeper não aparece.
Notarização, cask, versionamento e processo de release deixam de ser
necessários. Atualizar é `git pull` e recompilar.

## Critérios de sucesso

**Uma pessoa que não é o autor dita uma frase e vê o texto aparecer, tendo
falado só com o agente.** Sem o autor por perto e sem abrir o repositório.

O número que interessa é quantas vezes ela precisou de ajuda humana fora dos
três pontos que exigem clique dela (Command Line Tools, Microfone,
Acessibilidade). Zero é o alvo; cada ocorrência extra é um buraco no documento.

## Escopo v0

- `docs/INSTALL.md`, endereçado ao agente: pré-requisitos verificáveis, ordem
  dos passos, o que fazer em cada falha conhecida, e o que **não** tentar
  resolver sozinho.
- Os três pontos de intervenção humana marcados como tal, com o texto que o
  agente deve dizer à pessoa e como confirmar que ela fez.
- Uma verificação final de efeito, executável pelo agente.
- Um caminho alternativo para o modelo quando a rede bloqueia o download:
  copiar de quem já tem, com a validação de integridade que já existe.
- Nota no `README.md` apontando para esse caminho.

## Anti-escopo

- **Não** notarizar. A escolha de compilar localmente torna isso desnecessário,
  e notarizar custaria reconceder Microfone e Acessibilidade e órfãos o login
  item registrado.
- **Não** publicar cask do Homebrew. Sem binário pré-compilado, não há o que um
  cask instale.
- **Não** criar processo de release, versionamento ou changelog.
- **Não** fazer o app baixar o modelo. O binário continua sem código de rede —
  é a restrição que justifica o projeto, e há check de DoD verificando isso.
- **Não** tentar automatizar concessão de permissão do TCC. Não é possível, e
  fingir que é produziria uma instalação que se declara pronta e não funciona.
- **Não** dar suporte a Intel nem a macOS antigo. O `install.sh` já recusa os
  dois com mensagem clara.

## Contexto técnico

O que já existe e o documento aproveita:

- `scripts/build-app.sh` — clona o whisper.cpp num commit fixo, confere,
  compila estático, monta o bundle e assina com identidade local gerada na
  própria máquina.
- `scripts/install.sh` — recusa cedo o que não dá para consertar depois
  (não-Darwin, não-arm64, `/Applications` sem escrita), instala, verifica a
  assinatura, confere o modelo com piso de 400 MB, e já imprime as instruções de
  permissão. Boa parte do INSTALL.md é apontar para ele em vez de repetir.
- `scripts/setup-bench.sh` — baixa o checkpoint do CDN da OpenAI e converte,
  ~10 min. Existe porque a HuggingFace é bloqueada na rede corporativa do autor.
- `scripts/fetch-model.sh` — instala o modelo no lugar certo.
- `docs/armadilhas.md` — os erros já cometidos, que o agente deve ler antes de
  improvisar.

**Padrões que o documento precisa respeitar:**

- `verificacao-estrutural.md` — a verificação final não pode ser "o script disse
  ok". Tem que ser efeito observado de fora: processo vivo, ícone na barra,
  texto aparecendo.
- `falha-alta.md` — cada falha conhecida precisa nomear a ação de saída. Um
  agente que não sabe o que fazer com um erro improvisa, e improvisar em
  `security list-keychains` ou em `/Applications` estraga a máquina de alguém.

**Restrição que molda tudo:** Acessibilidade não concedida faz o app abrir,
mostrar ícone e não reagir à tecla — sem erro nenhum. É a armadilha nº 1 do
projeto, e é o modo de falha mais provável de uma instalação nova.

## Questões em aberto

- **Quais falhas o agente pode tentar resolver sozinho, e quais ele deve parar e
  perguntar?** Instalar `cmake` por Homebrew é seguro. Mexer na lista de
  keychains do usuário não é — o próprio `build-app.sh` tem um guarda-corpo lá
  porque `list-keychains -s` substitui a lista inteira. O documento precisa
  dessa fronteira explícita, e ela ainda não está desenhada.
- **Como o agente confirma que a pessoa concedeu a permissão**, sem confiar na
  palavra dela? `AXIsProcessTrusted()` responde por processo; do lado de fora,
  o caminho provável é conferir o efeito — ditar e ver se saiu texto.
- **O que o documento diz quando o download do modelo falha por rede
  corporativa?** O `install.sh` já sugere copiar de alguém, mas não existe
  instrução de como validar o arquivo copiado. O `ModelStore.isValid` faz isso
  dentro do app; falta o equivalente para o agente rodar antes.
