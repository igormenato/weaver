# Weaver

Weaver planeja sub-redes IPv4. O mesmo código é uma biblioteca Elixir e a Mix task `mix weaver`.

As funções públicas são `Weaver.fixed_masks/1`, `Weaver.vlsm_separated/1` e `Weaver.vlsm_sequential/1`. Cada uma recebe uma lista de inteiros com a contagem de máquinas por rede. O retorno é uma lista de mapas `%{machines, addr, prefix, mask}` na ordem da entrada.

## Instalar

Você precisa de Elixir `~> 1.18`.

```bash
git clone https://github.com/igormenato/weaver
cd weaver
mix deps.get
mix weaver --help
mix test
```

## Usar o CLI

Sem argumentos, o CLI pergunta quantas redes existem e quantas máquinas cada uma tem. A saída é tabela nos três modos.

```
$ mix weaver
Quantas redes?
> 3
Quantas máquinas na rede 1?
> 500
Quantas máquinas na rede 2?
> 100
Quantas máquinas na rede 3?
> 100

== Modo 1 - Fixo /16 e /24 ==
┌──────────┬──────────────────┬─────────┬─────────────────────┐
│ Máquinas │ Endereço de Rede │ Prefixo │ Máscara de Sub-rede │
├──────────┼──────────────────┼─────────┼─────────────────────┤
│   500    │    172.16.0.0    │   /16   │     255.255.0.0     │
│   100    │   192.168.0.0    │   /24   │    255.255.255.0    │
│   100    │   192.168.1.0    │   /24   │    255.255.255.0    │
└──────────┴──────────────────┴─────────┴─────────────────────┘

== Modo 2 - VLSM (separado) ==
┌──────────┬──────────────────┬─────────┬─────────────────────┐
│ Máquinas │ Endereço de Rede │ Prefixo │ Máscara de Sub-rede │
├──────────┼──────────────────┼─────────┼─────────────────────┤
│   500    │   192.168.0.0    │   /23   │    255.255.254.0    │
│   100    │   192.168.2.0    │   /25   │   255.255.255.128   │
│   100    │   192.168.3.0    │   /25   │   255.255.255.128   │
└──────────┴──────────────────┴─────────┴─────────────────────┘

== Modo 3 - VLSM (sequencial) ==
┌──────────┬──────────────────┬─────────┬─────────────────────┐
│ Máquinas │ Endereço de Rede │ Prefixo │ Máscara de Sub-rede │
├──────────┼──────────────────┼─────────┼─────────────────────┤
│   500    │   192.168.0.0    │   /23   │    255.255.254.0    │
│   100    │   192.168.2.0    │   /25   │   255.255.255.128   │
│   100    │  192.168.2.128   │   /25   │   255.255.255.128   │
└──────────┴──────────────────┴─────────┴─────────────────────┘
```

Para pular o diálogo, passe `--hosts`. A lista aceita vírgula ou espaço.

```bash
mix weaver --hosts "500,100,100"
mix weaver -H "500 100 100" -m separated
mix weaver -H 500,100,100 -m sequential --format json
```

`--mode` aceita `fixed`, `separated`, `sequential` ou `all`. O padrão é `all`. `--format` aceita `table` ou `json`. O padrão é `table`.

## Usar a biblioteca

```elixir
iex -S mix

Weaver.fixed_masks([500, 100, 100])
Weaver.vlsm_separated([500, 100, 100])
Weaver.vlsm_sequential([500, 100, 100])
```

Cada item tem `machines`, `addr`, `prefix` e `mask`. Contagem inválida ou falta de espaço levanta `ArgumentError`.

## Como os modos alocam

### Máscaras fixas

`Weaver.fixed_masks/1` não calcula prefixo. Ele escolhe `/16` ou `/24` pela contagem.

Se `hosts > 254`, a rede vai para `172.16.0.0/16`, depois `172.17.0.0/16`, até `172.31.0.0/16`. São 16 redes. A 17ª rede `/16` levanta erro.

Se `hosts <= 254`, a rede vai para `192.168.0.0/24`, depois `192.168.1.0/24`, até 256 redes. A 257ª rede `/24` também levanta erro.

As duas filas avançam à parte. Uma rede grande não consome índice da fila `/24`.

### VLSM

`Weaver.vlsm_separated/1` e `Weaver.vlsm_sequential/1` partem de `192.168.0.0/16`. `prefix_for_hosts/1` escolhe o menor prefixo com `2^(32 - prefixo) - 2` endereços úteis suficientes. O prefixo máximo é `/30`.

A alocação ordena a maior rede primeiro. O resultado volta na ordem original da lista.

Cada bloco alinha o cursor com `align_up` para o tamanho do prefixo. Se o último endereço passar de `192.168.255.255`, a função levanta erro.

Em `separated`, depois de alocar, o cursor faz `align_up` para o próximo `/24`. Redes menores não compartilham o mesmo `/24`.

Em `sequential`, o cursor vira `net + block_size`. O próximo bloco começa no endereço seguinte, ainda alinhado ao próprio prefixo.

## Licença

MIT. O texto está em `LICENSE`.
