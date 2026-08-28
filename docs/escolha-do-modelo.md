# Por que `large-v3-turbo`

Três candidatos, medidos em gravações reais de fala espontânea em português com
termos técnicos em inglês no meio — não em áudio de laboratório.

## A regra, aplicada nesta ordem

1. **Descartar** todo modelo que erre vocabulário a ponto de exigir edição
   manual. Latência não compra qualidade: se dá retrabalho, o ganho do ditado
   some.
2. Entre os que sobrarem, vence o mais rápido.
3. Se nenhum ficar dentro do teto, não escolher no grito — reabrir a discussão de
   arquitetura.

**Teto: 1500 ms**, do fim da fala ao texto pronto. Acima disso o fluxo quebra e a
pessoa volta a digitar.

## Latência

O Whisper processa em **janelas de 30 segundos**: um ditado de 5 s custa o mesmo
que um de 25 s. Não existe custo por segundo de áudio — existe custo por janela.

Os números descontam o carregamento do modelo, porque o app o mantém quente. E
vêm do cronômetro interno do processo, não do tempo de parede: parede inclui
spawn de processo e leitura do modelo do disco, que não existem no app.

| Modelo | Ditado até 30 s | Por janela | Teto de 1500 ms |
|---|---|---|---|
| large-v3-turbo-q5_0 | 782 ms | 820 ms | dentro |
| medium-q5_0 | 737 ms | 856 ms | dentro |
| small-q5_1 | 290 ms | 346 ms | dentro |

**Latência não discrimina.** Os três passam com folga, e a diferença entre turbo
e medium está dentro do ruído de uma execução. A decisão é de qualidade.

*(No app real, com o modelo já quente, um ditado curto mediu 599–609 ms.)*

## Qualidade

O que separou os modelos foi o vocabulário: nome de sistema em inglês no meio de
frase em português, termo de negócio, e verbo pouco frequente.

| Tipo de erro | turbo | medium | small |
|---|---|---|---|
| Nome de produto em inglês, duas palavras | correto | grafia trocada | correto |
| Substantivo comum ("investigação") | correto | correto | **outra palavra** |
| Verbo ("disparar") | correto | correto | **outro verbo** |
| Termo de negócio | correto | grafia inventada | grafia inventada |
| Verbo pouco frequente | errado | correto | errado |
| Alucinação | nenhuma | nenhuma | **inventou legenda** |

## Decisão

**`large-v3-turbo-q5_0`** — 547 MB, quantizado localmente a partir do checkpoint
da OpenAI.

**Justificativa, na ordem da regra:**

1. **`small-q5_1` está desclassificado**, apesar de ser 2,7× mais rápido. Ele não
   erra grafia, erra **sentido**: trocou um substantivo por outro e um verbo por
   outro, mudando o que a frase dizia. E alucinou uma legenda de música no fim de
   um áudio longo — que, num ditado, seria texto inventado colado no seu
   documento. A regra 1 é explícita.
2. **`medium-q5_0` também cai na regra 1.** Ele erra justamente o vocabulário que
   um ditado técnico precisa preservar: nome de produto e termo de negócio. Quem
   dita e precisa corrigir nome de sistema toda vez volta a digitar.
3. **Sobra `large-v3-turbo-q5_0`**, único a passar a regra 1.

## Limite conhecido: o teto só vale abaixo de 30 s

O teto de 1500 ms **não** sobrevive a um ditado que ocupe mais de uma janela: a
partir da segunda o custo dobra, e turbo (820 ms por janela) passa de 1500 ms. Só
`small` aguenta duas janelas.

Não é defeito — ditado é fala curta, e abaixo de 30 s todo modelo passa com folga.
Mas é limite real, e falar mais de meio minuto sem soltar a tecla tem espera
perceptível.

## Achado que continua aberto

Um verbo pouco frequente do domínio saiu errado de forma **consistente** em turbo
e small, e certo em medium. Nenhum modelo base acerta vocabulário específico de
forma confiável — é a evidência concreta a favor de vocabulário customizado
(prompt inicial), que este projeto ainda não tem.

## Como reproduzir

```bash
bash scripts/setup-bench.sh                  # monta os três modelos
bash scripts/record-fixture.sh 01-normal     # grave suas próprias amostras
bash scripts/bench.sh                        # mede e imprime a tabela
```

A bancada aborta se a inferência cair para CPU — um tempo medido assim é ~11×
maior e não representa o app. Ver `docs/armadilhas.md`.
