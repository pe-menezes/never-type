# Fixtures da bancada

Áudios de referência na **sua voz**, usados para medir latência e julgar
qualidade em pt-BR técnico. Nada aqui vai pro git além deste README.

## Como gravar

```bash
scripts/record-fixture.sh 01-fala-normal
scripts/record-fixture.sh 02-termos-tecnicos 18
scripts/record-fixture.sh 03-frase-curta 12
```

Sem argumento, o script lista os dispositivos de áudio disponíveis. O padrão é
o dispositivo `[0]`; passe o índice como terceiro argumento pra usar outro.

O script já grava em 16 kHz mono PCM 16-bit, que é o que o `whisper-cli`
consome. Não grave no QuickTime: sai em 44,1 kHz estéreo e a bancada rejeita.

## O que gravar

Pelo menos três áudios, cobrindo **ditado curto e longo**. A variação é o ponto:
o Whisper processa em janelas de 30 segundos, e só gravando abaixo e acima desse
degrau dá para enxergá-lo. Se todos tiverem o mesmo tamanho, a bancada mede uma
constante e você não descobre isso.

A regra é falar como você fala de verdade — ritmo normal, com as hesitações que
existem. Locução caprichada mede um cenário que não é o seu.

**01 — fala normal.** Um recado como você mandaria no Slack. Português
corrido, sem jargão pesado.

**02 — termos técnicos.** O caso difícil, e o que decide o modelo. Misture
português com termos em inglês do jeito que sai naturalmente, e inclua o nome
de pelo menos um sistema interno. Algo como:

> "Subi o deploy em staging mas o pod tá em CrashLoopBackOff, acho que é o
> health check. Vou olhar o dashboard no Datadog e depois abro uma issue pro
> time de plataforma."

**03 — frase curta.** Uma ou duas frases, do tamanho da maioria dos ditados
reais. Frase curta é onde o modelo mais erra e onde a latência mais aparece.

## O que NÃO gravar

Nada de dado pessoal ou sensível: documento, número de contrato, nome de cliente,
credencial. Para esses, o custo de um deslize não compensa nada.

Vocabulário técnico e nomes de sistema, por outro lado, são exatamente o que a
bancada precisa medir — não dá para avaliar se o modelo acerta o jargão que você
usa com frase inventada. Então fala real é aceitável, com uma consequência:

Este diretório está no `.gitignore`, e as transcrições em `bench-out/` também.
Não force `git add`. Se você citar trechos numa análise versionada, lembre que
eles saem do seu computador junto com o repositório.
