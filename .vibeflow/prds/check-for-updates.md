# PRD: Check for Updates no menu

> Gerado via /vibeflow:discover em 2026-09-18
> Origem: PR #14 (vcamaral, "Add self-update: check the git remote, apply on
> confirmation") e a conversa que o seguiu, com o autor.

## Problema

Atualizar o NeverType hoje exige abrir um terminal e rodar `bash
scripts/update.sh`, ou pedir a um agente. Quem instalou pelo Claude e não usa
git não sabe que existe versão nova, nem tem como aplicar sem voltar ao
terminal. O PR #14 resolveu isso com um checador automático dentro do app:
`git fetch` diário e no launch, ligado por padrão, e o `update.sh` disparado
pelo próprio app, que se mata no meio do script e deixa qualquer falha
posterior sem janela.

A discussão fechou em duas coisas. A promessa "sem rede" protege o conteúdo
ditado, não o socket em si: um `git fetch` num repositório público não carrega
nada do que a pessoa disse. E a checagem automática é a única parte que vaza
algo de verdade (IP e horário de uso, todo dia), além de ser a que ninguém
pediu.

## Público

Quem instalou o app a partir do clone, com o toolchain na máquina, e quer saber
se há versão nova e aplicá-la sem lembrar de comando nenhum. Inclui o autor, na
máquina de desenvolvimento, e quem só interage com o Claude.

## Solução proposta

Um item de menu, **Check for Updates…**, que só existe quando o checkout de
origem está acessível. No clique, e só no clique, o app roda `git fetch` no
checkout e compara instalado, local e remoto. Três respostas: já está na versão
mais nova; não deu para checar (rede, sem upstream); versão nova, com **Update
Now** e **Later**.

**Update Now abre o Terminal rodando `scripts/update.sh`**, o mesmo script de
sempre. A pessoa vê o log inteiro, o app fecha e reabre atualizado, e uma falha
no meio fica na janela do Terminal com a mensagem completa. Nada roda sozinho:
sem timer, sem checagem no launch, sem preferência para ligar ou desligar.

## Critérios de sucesso

- Com o app instalado atrás do remoto, um clique mostra "Update available" com
  os dois commits, e "Update Now" termina com o app reaberto na versão nova sem
  que a pessoa digite nada.
- Com tudo igual, o clique responde "up to date" e não faz mais nada.
- Sem rede, o clique responde que não conseguiu checar, em segundos, sem travar
  o app.
- Uma falha durante a atualização fica legível na janela do Terminal.
- Fora do clique, `nevertype.log` e um monitor de rede não registram conexão
  nenhuma do app.

## Escopo v0

- Linha `Check for Updates…` no `MenuLayout`, presente só com checkout
  acessível (carimbo `NeverTypeRepoRoot` no `Info.plist`, gravado por
  `build-app.sh`, e `scripts/update.sh` existindo nele).
- Regra de comparação e a chamada ao `git` em `NeverTypeCore`, com o comando
  entrando por parâmetro e timeout, e teste de cada desfecho.
- Os alertas no executável, e o `open -a Terminal` no "Update Now".
- A frase de exceção nos dois README, na seção de rede de `docs/reference.md`,
  no `CLAUDE.md`, e a nota em `.vibeflow/conventions.md` e `decisions.md`.

## Anti-escopo

- **Nenhuma checagem automática**: sem timer, sem checagem ao abrir, sem
  preferência em `UserDefaults`. Não é "desligado por padrão"; não existe.
- **Nenhuma rede além do `git fetch` do clique.** Nada de download de binário,
  telemetria ou verificação de versão por HTTP.
- **Aplicar dentro do app.** O `update.sh` mata o app no meio; sem janela de
  fora não há como reportar o que vem depois. Fica no Terminal.
- **Janela de progresso, log próprio, PID por variável de ambiente**: tudo do
  PR #14 que existia para aplicar dentro do app.
- **Atualização de cópia sem checkout** (o pacote distribuível, backlog A1):
  outra história, com outra ferramenta (Homebrew cask).

## Contexto técnico

- `scripts/update.sh` já compara instalado, local e remoto, recusa mudanças não
  commitadas e branch divergida, e termina com `verify-install.sh`. Não muda.
- `scripts/install.sh` mata a instância por `pkill -x NeverType`; rodando no
  Terminal, o app não é ancestral do script e o `pgrep` enxerga. O caminho por
  PID do PR #14 não entra.
- Padrões: `nucleo-testavel.md` (regra em Core, chamada de sistema por
  parâmetro, como `LoginItem`), `estado-consultado.md` (disponibilidade da
  linha conferida a cada abertura do menu, nunca guardada), `falha-alta.md`
  (cada desfecho tem alerta com a saída; a mensagem do `git` vai no alerta e no
  log), `isolamento-tipado.md` (`Task { @MainActor in }`, sem `assumeIsolated`).
- App aberto pelo Finder não herda `PATH`, proxy nem `SSH_AUTH_SOCK` do shell:
  os binários entram por caminho absoluto (`/usr/bin/git`, `/usr/bin/open`) e
  um fetch que dependa de proxy do `.zshrc` pode falhar dentro do app e passar
  no Terminal. É um desfecho previsto ("could not check"), não um bug.
- `git fetch` pode pendurar em rede que descarta pacotes: timeout obrigatório,
  e `GIT_TERMINAL_PROMPT=0` para não esperar credencial.

## Questões em aberto

Nenhuma.
