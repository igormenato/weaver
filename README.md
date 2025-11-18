# Weaver

🌐 **Planejador de sub-redes IPv4 em Elixir**

Ferramenta para calcular alocações de sub-redes IPv4 com três estratégias diferentes:

- **Máscaras fixas** - /16 e /24 baseado no número de hosts
- **VLSM separado** - Otimizado com gaps entre sub-redes
- **VLSM sequencial** - Empacotamento contíguo sem desperdício

## 🚀 Instalação

**Requisitos:** Elixir >= 1.18

**Setup do projeto:**

```bash
# Clone e prepare o ambiente
git clone https://github.com/igormenato/weaver
cd weaver
mix deps.get
mix compile
```

**Verificar instalação:**

```bash
mix test
```

## 🎮 Início Rápido

**📱 Via CLI (Interativo):**

```bash
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

**⚙️ Via CLI (Não-interativo):**

```bash
# Executa só um modo, saída em tabela (padrão)
mix weaver --hosts "500,100,100" --mode fixed
mix weaver -H "500 100 100" -m separated
mix weaver -H 500,100,100 -m sequential

# Saída JSON (para automatização)
mix weaver -H 500,100,100 --mode all --format json
```

**🔧 Via API (Programático):**

```elixir
iex> Weaver.fixed_masks([500, 100, 100])
[
  %{machines: 500, addr: "172.16.0.0", prefix: 16, mask: "255.255.0.0"},
  %{machines: 100, addr: "192.168.0.0", prefix: 24, mask: "255.255.255.0"},
  %{machines: 100, addr: "192.168.1.0", prefix: 24, mask: "255.255.255.0"}
]

iex> Weaver.vlsm_separated([500, 100, 100])
[
  %{machines: 500, addr: "192.168.0.0", prefix: 23, mask: "255.255.254.0"},
  %{machines: 100, addr: "192.168.2.0", prefix: 25, mask: "255.255.255.128"},
  %{machines: 100, addr: "192.168.3.0", prefix: 25, mask: "255.255.255.128"}
]

iex> Weaver.vlsm_sequential([500, 100, 100])
[
  %{machines: 500, addr: "192.168.0.0", prefix: 23, mask: "255.255.254.0"},
  %{machines: 100, addr: "192.168.2.0", prefix: 25, mask: "255.255.255.128"},
  %{machines: 100, addr: "192.168.2.128", prefix: 25, mask: "255.255.255.128"}
]
```

### 🧪 Servidor e Cliente TCP (JSON)

O Weaver pode ser executado como um servidor TCP que aceita requisições JSON delimitadas por nova linha e retorna respostas JSON também delimitadas por nova linha. A mesma máquina também pode agir como cliente usando a CLI.

Formato e Campos

- Requisições: JSON delimictadas por nova linha (packet: :line).
- Campo principal: `hosts` — lista de inteiros com número de máquinas por sub-rede.
- Campo opcional: `mode` — `fixed` | `separated` | `sequential` | `all` (padrão: `all`).

Exemplo de requisição:

```json
{"hosts": [500, 100, 100], "mode": "all"}\n
```

Exemplos de resposta:

- Sucesso: `{"status":"ok","data": {...}}\n`
- Erro: `{"status":"error","message":"..."}\n`

Servidor (dev)

Inicie o servidor para desenvolvimento:

```bash
mix weaver --serve
```

Por padrão o servidor é vinculado a `0.0.0.0` (todas as interfaces) a menos que você especifique `--socket-host`.

Cliente (CLI)

Chame um servidor em execução (local ou remoto):

```bash
# Chama servidor local (padrão localhost)
mix weaver --hosts "500,100,100" --socket-host 127.0.0.1 --socket-port 4040 --format json

# Chama servidor remoto com IP do servidor
mix weaver --hosts "500,100,100" --socket-host <endereco-servidor> --socket-port <porta-servidor> --format json
```

## 📐 Algoritmos e Regras

### 🏗️ Modo Fixo

Utiliza máscaras pré-determinadas baseadas no número de hosts:

- **Hosts > 254**: Máscara `/16`

  - Faixa: `172.16.0.0/16`, `172.17.0.0/16`, etc.
  - Capacidade: ~65.000 hosts por rede

- **Hosts ≤ 254**: Máscara `/24`
  - Faixa: `192.168.0.0/24`, `192.168.1.0/24`, etc.
  - Capacidade: 254 hosts por rede

**Limitações**: Verifica espaço disponível e gera erro quando excede capacidade.

### 🧩 VLSM (Variable Length Subnet Mask)

Cálculo dinâmico de máscaras otimizadas:

- **Espaço base**: `192.168.0.0/16` (65.536 endereços)
- **Cálculo automático**: Menor prefixo que comporta N hosts
  - Fórmula: `hosts_utilizáveis = 2^(32-prefixo) - 2`
- **Estratégia**: Ordena por tamanho decrescente para otimizar espaço
- **Resultado**: Mantém ordem original da entrada

#### Modalidades VLSM:

**🔄 Separado**

- Avança para próximo limite `/24` após cada alocação
- Evita conflitos entre sub-redes
- Pode deixar espaços não utilizados

**⚡ Sequencial**

- Empacotamento contíguo sem desperdício
- Alinhamento natural de cada sub-rede
- Maximiza aproveitamento do espaço

### 📊 Exemplo Comparativo

Para entrada `[500, 100, 100]` hosts, veja como cada modo aloca:

#### 🏗️ Modo Fixo

```
Rede 1: 500 hosts → 172.16.0.0/16  (faixa 172.16.x.x)
Rede 2: 100 hosts → 192.168.0.0/24  (faixa 192.168.0.x)
Rede 3: 100 hosts → 192.168.1.0/24  (faixa 192.168.1.x)
```

> Usa faixas diferentes: /16 para >254 hosts, /24 para ≤254 hosts

#### 🧩 VLSM Separado

```
Rede 1: 500 hosts → 192.168.0.0/23   (192.168.0.0 - 192.168.1.255)
Rede 2: 100 hosts → 192.168.2.0/25   (192.168.2.0 - 192.168.2.127)
Rede 3: 100 hosts → 192.168.3.0/25   (192.168.3.0 - 192.168.3.127)
```

> Tudo na base 192.168.x.x, mas pula para próximo /24 entre alocações

#### ⚡ VLSM Sequencial

```
Rede 1: 500 hosts → 192.168.0.0/23     (192.168.0.0 - 192.168.1.255)
Rede 2: 100 hosts → 192.168.2.0/25     (192.168.2.0 - 192.168.2.127)
Rede 3: 100 hosts → 192.168.2.128/25   (192.168.2.128 - 192.168.2.255)
```

> Empacota sem desperdício: redes 2 e 3 compartilham o mesmo /24

## 📄 Licença

Licença MIT
