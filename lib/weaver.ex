defmodule Weaver do
  import Bitwise

  @moduledoc """
  Planejamento de sub-redes IPv4 com três modos:

  1) Máscaras fixas /16 e /24 baseado na quantidade de hosts
  2) VLSM com endereços separados (avançar para o próximo /24 entre alocações)
  3) VLSM com endereços sequenciais (empacotado)

  Todas as funções recebem uma lista de inteiros (hosts por rede) e retornam uma lista
  de mapas na ordem original da entrada: `%{machines, addr, prefix, mask}`.
  """

  @type machines :: non_neg_integer()
  @type allocation :: %{machines: machines(), addr: String.t(), prefix: 0..32, mask: String.t()}

  @doc """
  Modo 1: Máscaras fixas /16 (se máquinas > 254) e /24 (caso contrário).

  - Redes /16 alocadas a partir de 172.16.0.0/16, depois 172.17.0.0/16, ...
  - Redes /24 alocadas a partir de 192.168.0.0/24, depois 192.168.1.0/24, ...

  Limites: até 16 redes /16 (172.16..172.31). Para /24 até 256 redes.
  """
  @spec fixed_masks([machines()]) :: [allocation()]
  def fixed_masks(machines_list) when is_list(machines_list) do
    # Preparar índices para pools separados
    {res, _i16, _i24} =
      Enum.reduce(Enum.with_index(machines_list), {[], 16, 0}, fn {m, idx}, {acc, i16, i24} ->
        cond do
          not (is_integer(m) and m > 0) ->
            raise ArgumentError, "Quantidade de máquinas inválida no índice #{idx}: #{inspect(m)}"

          m > 254 and i16 > 31 ->
            raise ArgumentError,
                  "Excedeu a capacidade de /16 (172.16.0.0/16 .. 172.31.0.0/16)"

          m > 254 ->
            addr = ip_to_string({172, i16, 0, 0})
            mask = prefix_to_mask(16)
            {[%{machines: m, addr: addr, prefix: 16, mask: mask} | acc], i16 + 1, i24}

          i24 > 255 ->
            raise ArgumentError, "Excedeu a capacidade de /24 em 192.168.0.0/16"

          true ->
            addr = ip_to_string({192, 168, i24, 0})
            mask = prefix_to_mask(24)
            {[%{machines: m, addr: addr, prefix: 24, mask: mask} | acc], i16, i24 + 1}
        end
      end)

    res |> Enum.reverse()
  end

  @doc """
  Modo 2: VLSM com endereços separados.

  - Base: 192.168.0.0/16
  - Para cada rede, calcula-se o menor prefixo que acomode `machines` (2^(32-p)-2 >= machines).
  - Aloca por ordem decrescente de tamanho (maior primeiro), porém o resultado é
    devolvido na ordem original.
  - Entre alocações, o cursor avança para o PRÓXIMO limite de /24, garantindo
    que redes menores não fiquem "coladas" no mesmo /24 (ex.: 192.168.2.0/25 e
    depois 192.168.3.0/25).
  """
  @spec vlsm_separated([machines()]) :: [allocation()]
  def vlsm_separated(machines_list) when is_list(machines_list) do
    do_vlsm(machines_list, :separated)
  end

  @doc """
  Modo 3: VLSM com endereços sequenciais (empacotado).

  - Base: 192.168.0.0/16
  - Alinhamento natural por prefixo, sem "pular" para o próximo /24 entre
    alocações, resultando em ranges contíguos quando possível.
  """
  @spec vlsm_sequential([machines()]) :: [allocation()]
  def vlsm_sequential(machines_list) when is_list(machines_list) do
    do_vlsm(machines_list, :sequential)
  end

  # =========================
  # Implementação VLSM
  # =========================

  defp do_vlsm([], _mode), do: []

  defp do_vlsm(machines_list, mode) do
    base_int = ip_tuple_to_int({192, 168, 0, 0})
    base_end = ip_tuple_to_int({192, 168, 255, 255})

    # Preparar entradas com índice original e prefixo necessário
    entries =
      machines_list
      |> Enum.with_index()
      |> Enum.map(fn {m, idx} ->
        unless is_integer(m) and m > 0 do
          raise ArgumentError, "Quantidade de máquinas inválida no índice #{idx}: #{inspect(m)}"
        end

        p = prefix_for_hosts(m)
        %{idx: idx, machines: m, prefix: p}
      end)

    # Ordenar por necessidade (maior rede primeiro) -> menor prefixo primeiro
    sorted = Enum.sort_by(entries, fn e -> {e.prefix, -e.machines} end)

    {allocs_map, _cursor} =
      Enum.reduce(sorted, {%{}, base_int}, fn e, {acc, cursor} ->
        block_size = 1 <<< (32 - e.prefix)

        # Alinha cursor para o próximo limite de bloco (round up)
        net = align_up(cursor, block_size)

        # Verifica se cabe no /16 base
        last_ip = net + block_size - 1

        if last_ip > base_end do
          raise ArgumentError,
                "Alocação excede 192.168.0.0/16 para a rede com #{e.machines} máquinas (/#{e.prefix})."
        end

        # Atualiza cursor de acordo com o modo
        next_cursor =
          case mode do
            :sequential ->
              net + block_size

            :separated ->
              # Pular para o próximo /24 após a alocação
              # 256 endereços = /24
              align_up(net + block_size, 1 <<< 8)
          end

        mask = prefix_to_mask(e.prefix)

        acc =
          Map.put(acc, e.idx, %{
            machines: e.machines,
            addr: int_to_ip(net),
            prefix: e.prefix,
            mask: mask
          })

        {acc, next_cursor}
      end)

    # Remonta na ordem original
    0..(length(machines_list) - 1)
    |> Enum.map(&Map.fetch!(allocs_map, &1))
  end

  # =========================
  # Helpers de IP e cálculos
  # =========================

  @doc false
  @spec prefix_for_hosts(pos_integer()) :: 2..30
  def prefix_for_hosts(n) when is_integer(n) and n > 0 do
    # Encontrar o menor h tal que 2^h - 2 >= n (hosts utilizáveis)
    # Depois prefix = 32 - h; limitar a /30 no máximo (não usamos /31,/32)
    # começar em /30 => h=2 (4 endereços, 2 utilizáveis)
    h = min_host_bits(n, 2)
    p = 32 - h
    if p > 30, do: 30, else: p
  end

  defp min_host_bits(_n, h) when h >= 30, do: 30

  defp min_host_bits(n, h) do
    usable = (1 <<< h) - 2
    if usable >= n, do: h, else: min_host_bits(n, h + 1)
  end

  @doc false
  @spec ip_to_string({0..255, 0..255, 0..255, 0..255}) :: String.t()
  def ip_to_string({a, b, c, d}), do: Enum.join([a, b, c, d], ".")

  @doc false
  @spec ip_tuple_to_int({0..255, 0..255, 0..255, 0..255}) :: non_neg_integer()
  def ip_tuple_to_int({a, b, c, d}) do
    (a <<< 24) + (b <<< 16) + (c <<< 8) + d
  end

  @doc false
  @spec int_to_ip(non_neg_integer()) :: String.t()
  def int_to_ip(i) when is_integer(i) and i >= 0 and i < 4_294_967_296 do
    a = i >>> 24 &&& 0xFF
    b = i >>> 16 &&& 0xFF
    c = i >>> 8 &&& 0xFF
    d = i &&& 0xFF
    ip_to_string({a, b, c, d})
  end

  @doc false
  @spec align_up(non_neg_integer(), pos_integer()) :: non_neg_integer()
  def align_up(n, block_size) do
    remainder = rem(n, block_size)
    if remainder == 0, do: n, else: n + (block_size - remainder)
  end

  @doc false
  @spec prefix_to_mask(0..32) :: String.t()
  def prefix_to_mask(prefix) when prefix >= 0 and prefix <= 32 do
    mask_int = 0xFFFFFFFF <<< (32 - prefix) &&& 0xFFFFFFFF
    int_to_ip(mask_int)
  end
end
