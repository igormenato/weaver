defmodule Mix.Tasks.Weaver do
  use Mix.Task

  @shortdoc "Calcular endereçamento IPv4 (3 modos)"

  @moduledoc """
  Task interativa para calcular endereçamento para uma topologia a partir do número
  de redes e hosts por rede. Imprime três modos:

  1) Fixo /16 e /24
  2) VLSM com endereços separados
  3) VLSM com endereços sequenciais
  """

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Quantas redes?")
    n = read_int!()

    machines =
      1..n
      |> Enum.map(fn i ->
        Mix.shell().info("Quantas máquinas na rede #{i}?")
        read_int!()
      end)

    with {:ok, fixed} <- safe(fn -> Weaver.fixed_masks(machines) end),
         {:ok, sep} <- safe(fn -> Weaver.vlsm_separated(machines) end),
         {:ok, seq} <- safe(fn -> Weaver.vlsm_sequential(machines) end) do
      print_table("Modo 1 - Fixo /16 e /24", fixed)
      print_table("Modo 2 - VLSM (separado)", sep)
      print_table("Modo 3 - VLSM (sequencial)", seq)
    else
      {:error, msg} ->
        Mix.shell().error("Erro: #{msg}")
    end
  end

  defp read_int! do
    case IO.gets("> ") do
      :eof ->
        raise "Entrada encerrada"

      {:error, reason} ->
        raise "Erro lendo entrada: #{inspect(reason)}"

      line ->
        line
        |> String.trim()
        |> Integer.parse()
        |> case do
          {v, ""} when v > 0 ->
            v

          _ ->
            Mix.shell().error("Digite um inteiro positivo.")
            read_int!()
        end
    end
  end

  defp print_table(title, rows) do
    Mix.shell().info("")
    Mix.shell().info("== #{title} ==")

    # Calcular larguras dinâmicas das colunas
    machines_strs = Enum.map(rows, &Integer.to_string(&1.machines))
    addr_strs = Enum.map(rows, & &1.addr)

    width1 =
      max(String.length("Máquinas"), Enum.max([0 | Enum.map(machines_strs, &String.length/1)])) +
        2

    width2 =
      max(
        String.length("Endereço de Rede"),
        Enum.max([0 | Enum.map(addr_strs, &String.length/1)])
      ) + 2

    header =
      String.pad_trailing("Máquinas", width1) <>
        String.pad_trailing("Endereço de Rede", width2) <>
        "Máscara"

    Mix.shell().info(header)

    Enum.each(rows, fn r ->
      machines = Integer.to_string(r.machines)
      addr = r.addr

      line =
        String.pad_trailing(machines, width1) <>
          String.pad_trailing(addr, width2) <>
          "/#{r.prefix}"

      Mix.shell().info(line)
    end)
  end

  defp safe(fun) when is_function(fun, 0) do
    try do
      {:ok, fun.()}
    rescue
      e in [ArgumentError] -> {:error, e.message}
      e -> {:error, Exception.message(e)}
    end
  end
end
