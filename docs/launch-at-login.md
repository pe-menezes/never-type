# Quanto custa abrir com o sistema

Medido em 2026-08-28, macOS 26.2, Apple Silicon, modelo
`ggml-large-v3-turbo-q5_0.bin` (547 MB).

O app não muda nada no lançamento por causa desta opção: ele carrega o modelo e
aquece exatamente como sempre fez. O que muda é **quando** essa conta é paga —
antes você escolhia a hora abrindo o app, agora ela cai junto com o login.

## O número

Cronômetro de fora do processo: de `open` até a linha aparecer no log do app.
Não é o log se auto-medindo.

| | ícone na barra | pronto para ditar | carga do modelo |
|---|---|---|---|
| **page cache frio** | 784 ms | **8303 ms** | 6874 ms |
| page cache quente | 142 ms | 951 ms | 178 ms |
| page cache quente (2ª) | 162 ms | 965 ms | 172 ms |

O aquecimento é constante — 614 a 622 ms nas três execuções. **Toda a diferença
está em ler 547 MB do disco: 6874 ms contra ~175 ms, quase 39×.**

## Por que a linha fria é a que importa aqui

Logo depois do login o page cache está vazio por definição. Então o custo real de
abrir com o sistema é a linha de cima, não a de baixo — e as medições que você
faria testando à mão, com o modelo já lido uma vez, dão o número errado por
uma ordem de grandeza.

E 8303 ms é **piso**, não teto: foi medido numa sessão já em regime. No login de
verdade isso disputa disco e CPU com Spotlight, iCloud e o resto do que sobe
junto. O número honesto do boot só sai reiniciando a máquina.

## O que isso significa na prática

O ícone aparece em 784 ms. O que atrasa é ficar **pronto para ditar**: nos
primeiros ~8 s depois do login, segurar ⌘ direito grava, mas a transcrição
espera o modelo.

A spec decidiu não carregar o modelo sob demanda, deixando para revisitar com o
número medido na mão. O número está aqui, e ele não muda a decisão: ninguém dita
oito segundos depois de ligar o computador. Carregar sob demanda só empurraria a
mesma espera para o primeiro ditado do dia — que é justamente quando a pessoa
está esperando o texto aparecer.

O que mudaria a decisão seria o ícone demorar, e ele não demora.

## Como refazer a medição

**No boot, sem ferramenta nenhuma:** reinicie, abra o menu da bandeja e leia a
linha `Modelo: Metal · carga N ms · aquecimento N ms`. O app já se mede sozinho, e
essa é a carga fria de verdade. É a forma certa de refazer este número — as
outras abaixo servem para medir fora do boot.

Para cronometrar um lançamento qualquer, de fora do processo:

```bash
bash scripts/build-app.sh
pkill -x NeverType
rm -f ~/Library/Application\ Support/NeverType/nevertype.log
# cronometre daqui até a linha "modelo:" aparecer no log
open build/NeverType.app
```

Só não confunda os dois: sem reiniciar, o page cache já está quente da execução
anterior e você mede 951 ms achando que mediu o boot.
