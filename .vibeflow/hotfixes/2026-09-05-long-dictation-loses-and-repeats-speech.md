# Hotfix: long-dictation-loses-and-repeats-speech

origin: session
status: verified

## Symptom
Ditado longo volta cortado e com frases repetidas. Visto em 2026-09-05, no app,
num ditado de quase seis minutos. O log do app:

```
nevertype: recorded: 5740800 samples (358.8 s)
nevertype: transcribed in 8064 ms: 1945 chars
```

O áudio foi capturado inteiro: 5740800 amostras são os 358,8 s falados. Os
outros ditados do mesmo dia renderam perto de 14 caracteres por segundo de fala
(414 chars para 34,0 s; 491 para 33,4 s; 338 para 21,5 s; 471 para 35,3 s), o
que projeta perto de 4800 caracteres para 358,8 s. Vieram 1945, cerca de 40%.

O texto que sobrou, em `historico.json`, repete e degenera no fim:

```
Quem quiser usar. Quem quiser usar. Quem quiser usar.
Não é melhor escrever não assim, né? Não é melhor escrever não assim, né?
E aí, eu já resolvi. eu vou fazer o meu nome. e eu vou te dar um pouco.
```

Reproduzido fora do app com `whisper-cli` na mesma lib estática, mesmo modelo
(`large-v3-turbo-q5_0`), greedy e 4 threads, sobre 460 s de fala pt-BR com 60
marcadores numerados. A única variável entre as duas rodadas é a flag:

| rodada | palavras certas de 1120 | marcadores | parede |
|---|---|---|---|
| `-nt` (config do app) | 645 (57,6%) | 33/60 | 23,7 s |
| sem `-nt` | 1101 (98,3%) | 60/60 | 15,2 s |

Os marcadores perdidos caem em blocos contíguos (9-13, 21-24, 42-47, 49-60),
que é a assinatura de janela inteira descartada, e o texto termina em loop:
`Marcador 44. Marcador 44. Marcador 44.`

## Checkpoint
hypothesis: `params.no_timestamps = true` em `Transcriber.swift`. Sem os
tokens de timestamp o `has_ts` do whisper.cpp nunca liga, o avanço da janela fica
preso em 30 s fixos e cada fronteira corta no meio da frase. A janela seguinte
começa sem borda de frase, o decoder degenera em repetição, e quando a confiança
cai a janela inteira é descartada. Os dois trechos estão em
`whisper_full_with_state`, whisper.cpp v1.9.2, o commit que `build-app.sh` fixa.
O erro acumula ao longo do ditado.
falsification_test: transcrever o mesmo áudio acima de 30 s com a flag desligada
e a perda continuar.
blind_spots: a degradação é cumulativa e não aparece cedo. Cortando a mesma
fixture em vários comprimentos e transcrevendo cada um com a flag ligada e
desligada, em porcentagem das palavras faladas:

| áudio | com a flag | sem a flag |
|---|---|---|
| 119 s | 97,3% | 96,7% |
| 180 s | 98,0% | 97,3% |
| 243 s | 91,3% | 97,2% |
| 346 s | 92,7% | 97,6% |
| 460 s | 57,6% | 98,3% |

Até três janelas as duas configurações empatam dentro do ruído. Qualquer teste de
regressão precisa de áudio bem acima disso para ser vermelho de verdade, e é por
isso que a fixture tem 460 s. A decodificação greedy é determinística: três
rodadas da configuração quebrada sobre o mesmo áudio devolveram os mesmos 33 de
60 marcadores. Não foi investigado por que o padrão
do whisper é `false` e este projeto ligou: a linha entrou no commit de rename
(`c97f01b`) sem justificativa registrada.

## Preservation
- Ditado abaixo de 30 s continua com o mesmo texto e a mesma latência: dentro de
  uma janela a flag não muda o caminho de decodificação.
- O texto entregue continua sem timestamps: `whisper_full_get_segment_text`
  devolve só o texto do trecho, e `print_timestamps` já é `false`.
- Nenhuma chamada de rede nova.

## Eliminated / Evidence

## Root cause
`params.no_timestamps = true` em `Transcriber.swift`. Sem os tokens de timestamp
o `has_ts` do whisper.cpp nunca liga, o avanço da janela fica preso em 30 s
cegos, e cada fronteira corta no meio da frase. A janela seguinte abre sem borda
de frase, o decoder degenera em repetição, e quando a confiança cai a janela
inteira é descartada. Dentro de uma janela nada muda, que é por que isso
embarcou: todo ditado até aqui era menor que 30 s, e `docs/model-choice.md` já
registrava que acima de duas janelas ninguém tinha medido.

A linha entrou no commit de rename (`c97f01b`) sem justificativa registrada. O
padrão do whisper sempre foi `false`.

## Fix
files_changed: Sources/NeverTypeCore/Transcriber.swift

Uma linha, `true` para `false`, com o comentário registrando o custo medido.
Nada mais muda no caminho: `print_timestamps` já era `false` e
`whisper_full_get_segment_text` devolve só o texto do trecho, então nenhum
timestamp chega à saída. O que os timestamps decidem é onde a próxima janela
começa.

Sai mais rápido também. Sobre os mesmos 460 s: 23,7 s de parede com a flag
ligada contra 15,2 s desligada, porque o loop de repetição queima tokens e
dispara o fallback de temperatura. No teste da suíte, 26,4 s vermelho contra
13,2 s verde.

## DoD
- [x] `LongDictationTests.swift` vermelho antes da correção pelas duas faces do
  defeito (13 de 60 marcadores ausentes, "Marcador número 51" nove vezes
  seguidas) e verde depois.
- [x] `swift test` verde: 171 testes em 20 suítes, contra 169 em 18 antes.
  Parede 38,9 s, porque as três transcrições longas rodam em paralelo.
- [x] O defeito também é vermelho em fala gravada, não só na sintetizada:
  `RecordedLongDictationTests` deu 2,7 caracteres por segundo com a flag ligada
  contra o piso de 8, e passa com ela desligada.
- [x] Ditado de 20 s devolve texto idêntico com a flag ligada e desligada,
  caractere por caractere. É a propriedade de preservação que mais importa,
  porque é o formato de quase todo ditado.
- [x] O texto entregue não traz timestamp: asserção no próprio teste, sobre o
  texto que sai de `Transcriber.transcribe`.

## Regression
Dois testes, no mesmo arquivo, com oráculos diferentes de propósito.

WHEN 460 s de fala pt-BR sintetizada, com 60 marcadores numerados, passam por
`Transcriber.transcribe` THEN no máximo 6 marcadores faltam, nenhuma frase volta
mais de duas vezes seguidas, e o texto não traz timestamp. Este roda em qualquer
máquina com o modelo instalado, porque a fixture se sintetiza sozinha.

WHEN uma gravação real acima de 4 min em `fixtures/` passa por
`Transcriber.transcribe` THEN volta pelo menos 8 caracteres por segundo de áudio
e nenhuma frase se repete mais de duas vezes. Sem transcrito de referência: a
gravação é fala de alguém, e as duas leituras são de forma, não de conteúdo. As
mensagens de falha carregam número e nada mais, então uma rodada vermelha não
imprime a gravação no log.

test: Tests/NeverTypeCoreTests/LongDictationTests.swift
oracle_type: specified (fixture sintetizada) + implicit (gravação real)
reproduction: real
verification: red-green

## Deviations
- O áudio do ditado real de 358,8 s não existe mais. `last.wav` guarda só o
  último ditado e já tinha sido sobrescrito quando a investigação começou; o que
  sobrou foi o texto em `historico.json` e as linhas do log. Daí as duas
  fixtures: a sintetizada reproduz o defeito em qualquer máquina, e a gravada
  fecha a reprodução em fala real.
- O teste custa ~13 s por `swift test` numa máquina com o modelo instalado, e é
  de longe o mais lento da suíte. É o preço de exercitar mais de duas janelas,
  que é onde este defeito mora. Ele sincroniza a fixture em `.cache/` e só
  re-sintetiza quando o roteiro muda.
- Confirmado em fala real, e o resultado é pior que a fixture dizia. Uma
  mensagem de voz de 404 s, transcrita pelas duas configurações:

  | | chars | palavras | chars/s |
  |---|---|---|---|
  | com a flag | 1079 | 201 | 2,7 |
  | sem a flag | 6399 | 962 | 15,8 |

  A configuração quebrada guardou 19% das palavras, contra 58% na fixture
  sintetizada de comprimento parecido. Fala real tem pausa, respiração e ruído,
  e a janela cai no descarte por baixa confiança com muito mais facilidade. É o
  que explica os 40% do ditado que originou este hotfix.

  E o modo de falha é outro: a maior repetição consecutiva foi 1 nas duas
  rodadas. Em fala real a janela some calada, sem deixar rastro no texto, o que
  é pior que o loop porque não dá para perceber lendo. A asserção de repetição
  do teste não pegaria este caso; a de cobertura de marcadores pega, e a de
  densidade também.

- A fixture gravada não tem transcrito de referência, e o teste foi desenhado
  para não precisar de um. Ele lê duas formas, densidade de caracteres por
  segundo e maior repetição consecutiva, e as mensagens de falha carregam número
  e nada mais. `fixtures/` não é versionado. Nada do que foi falado existe em
  arquivo deste repositório, e é assim que dá para fechar em `reproduction: real`
  sem publicar áudio de ninguém.

- `TranscriberTests` estava sendo pulado nesta máquina por falta de fixture e
  agora roda, transcrevendo a mesma gravação uma segunda vez. É trabalho
  repetido: as asserções dele são mais fracas que as do teste de densidade.
  Some sozinho quando os fixtures curtos 01 a 03 do README forem gravados,
  porque `firstFixture()` pega o primeiro em ordem alfabética.

- A contagem de testes foi sincronizada nos cinco lugares que a citavam
  (`CLAUDE.md` duas vezes, `README.md`, `README.pt-BR.md`, `.vibeflow/index.md`):
  169 em 18 suítes para 171 em 20. É consequência direta desta mudança, não
  escopo novo.
- Achados colaterais, adiados por serem outro assunto:
  - `carry_initial_prompt` foi medido em 2026-09-05 e **o achado morreu**. A
    hipótese era que o vocabulário só ancorava a primeira janela. Sobre 415 s
    com três termos, contando acertos por terço do áudio: sem prompt 0 de 60,
    com prompt 40 de 40 nos dois termos que o modelo consegue produzir, e
    distribuído por igual (7/6/7 e 6/7/7). Ligar `carry_initial_prompt` deu
    resultado idêntico. O `prompt_past` é reconstruído a cada janela a partir do
    prompt usado, então os termos rolam adiante enquanto couberem no contexto.
    Não medido: vocabulário grande em áudio muito longo, onde eles podem ser
    empurrados para fora.
  - A pílula ficava em "Writing" sem progresso durante a transcrição inteira,
    13 s no áudio desta fixture. **Feito no mesmo dia.** O
    `progress_callback` do whisper agora chega ao orb pela borda dele, que
    vira anel de progresso enquanto escreve. O teste longo lê os mesmos
    números e exige que subam e cheguem ao fim; o desenho em si não tem
    teste, porque `PillView` vive no alvo executável e a suíte é do
    `NeverTypeCore`.
  - `docs/model-choice.md` diz que acima de duas janelas ninguém mediu. Agora
    foi medido, e a seção merece a correção.
