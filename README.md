# Weaver

🌐 **Planejador de sub-redes IPv4 em Elixir**

Ferramenta para calcular alocações de sub-redes IPv4 com três estratégias diferentes:

- **Máscaras fixas** - /16 e /24 baseado no número de hosts
- **VLSM separado** - Otimizado com gaps entre sub-redes
- **VLSM sequencial** - Empacotamento contíguo sem desperdício

## 🚀 Instalação

**Requisitos:** Elixir >= 1.18

**Executar testes:**

```bash
mix test
```

**Executar CLI interativa:**

```bash
mix weaver
```

## 🔧 Uso Programático (API)

```elixir
iex> Weaver.fixed_masks([500, 100, 100])
[%{machines: 500, addr: "172.16.0.0", prefix: 16},
 %{machines: 100, addr: "192.168.0.0", prefix: 24},
 %{machines: 100, addr: "192.168.1.0", prefix: 24}]

iex> Weaver.vlsm_separated([500, 100, 100])
[%{machines: 500, addr: "192.168.0.0", prefix: 23},
 %{machines: 100, addr: "192.168.2.0", prefix: 25},
 %{machines: 100, addr: "192.168.3.0", prefix: 25}]

iex> Weaver.vlsm_sequential([500, 100, 100])
[%{machines: 500, addr: "192.168.0.0", prefix: 23},
 %{machines: 100, addr: "192.168.2.0", prefix: 25},
 %{machines: 100, addr: "192.168.2.128", prefix: 25}]
```

## 💻 Uso via CLI

Execute a task interativa:

```bash
mix weaver
```

A ferramenta solicitará:

1. Número total de redes
2. Número de hosts para cada rede
3. Apresentará três tabelas comparativas dos diferentes modos

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

MIT License - consulte o arquivo LICENSE para detalhes.
