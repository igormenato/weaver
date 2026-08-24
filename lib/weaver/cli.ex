defmodule Weaver.CLI do
  @moduledoc """
  Local CLI for Weaver. `mix weaver` calls `main/1`.
  """

  @planners [
    {"fixed", &Weaver.fixed_masks/1, "Modo 1 - Fixo /16 e /24"},
    {"separated", &Weaver.vlsm_separated/1, "Modo 2 - VLSM (separado)"},
    {"sequential", &Weaver.vlsm_sequential/1, "Modo 3 - VLSM (sequencial)"}
  ]

  def main(args) do
    {opts, _rest, invalid} = parse_args(args)

    cond do
      invalid != [] ->
        print_error("opção inválida: #{inspect(invalid)}")
        print_usage()

      Keyword.get(opts, :help, false) ->
        print_usage()

      Keyword.has_key?(opts, :hosts) ->
        hosts_csv = Keyword.fetch!(opts, :hosts)
        handle_hosts(opts, hosts_csv)

      true ->
        run_interactive()
    end
  end

  defp parse_args(args) do
    OptionParser.parse(args,
      switches: [
        hosts: :string,
        mode: :string,
        format: :string,
        help: :boolean
      ],
      aliases: [H: :hosts, m: :mode, f: :format, h: :help]
    )
  end

  defp handle_hosts(opts, hosts_csv) do
    case parse_hosts(hosts_csv) do
      {:ok, machines} ->
        mode = Keyword.get(opts, :mode, "all")
        format = Keyword.get(opts, :format, "table")
        render_outputs(machines, mode, format)

      {:error, msg} ->
        print_error(msg)
    end
  end

  defp parse_hosts(hosts_csv) do
    hosts_csv
    |> String.split([",", " "], trim: true)
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case parse_positive_int(part) do
        {:ok, n} -> {:cont, {:ok, [n | acc]}}
        :error -> {:halt, {:error, "quantidade de máquinas inválida: #{inspect(part)}"}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, "lista de hosts vazia"}
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end

  defp run_interactive do
    IO.puts("Quantas redes?")
    n = read_int!()

    machines =
      1..n
      |> Enum.map(fn i ->
        IO.puts("Quantas máquinas na rede #{i}/#{n}?")
        read_int!()
      end)

    render_outputs(machines, "all", "table")
  end

  defp render_outputs(machines, mode, format) do
    mode = String.downcase(mode)
    format = String.downcase(format)

    planners =
      if mode == "all",
        do: @planners,
        else: Enum.filter(@planners, fn {name, _, _} -> name == mode end)

    cond do
      format not in ["table", "json"] ->
        print_error("formato inválido: #{format}")

      planners == [] ->
        print_error("modo inválido: #{mode}")

      true ->
        case run_planners(machines, planners) do
          {:error, msg} ->
            print_error(msg)

          {:ok, results} ->
            print_results(results, mode, format)
        end
    end
  end

  defp run_planners(machines, planners) do
    Enum.reduce_while(planners, {:ok, []}, fn {name, fun, title}, {:ok, acc} ->
      try do
        {:cont, {:ok, [{name, title, fun.(machines)} | acc]}}
      rescue
        e in ArgumentError -> {:halt, {:error, e.message}}
      end
    end)
    |> then(fn
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end)
  end

  defp print_results(results, "all", "json") do
    print_json(Map.new(results, fn {name, _title, rows} -> {name, rows} end))
  end

  defp print_results(results, _mode, "json") do
    Enum.each(results, fn {_name, _title, rows} -> print_json(rows) end)
  end

  defp print_results(results, _mode, _format) do
    Enum.each(results, fn {_name, title, rows} -> print_table(title, rows) end)
  end

  defp read_int! do
    case IO.gets("> ") do
      :eof ->
        raise "Entrada encerrada"

      {:error, reason} ->
        raise "Erro lendo entrada: #{inspect(reason)}"

      line ->
        case parse_positive_int(line) do
          {:ok, n} ->
            n

          :error ->
            IO.puts(:stderr, "Digite um inteiro positivo.")
            read_int!()
        end
    end
  end

  defp parse_positive_int(s) do
    case Integer.parse(String.trim(s)) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> :error
    end
  end

  defp print_table(title, rows) do
    header = ["Máquinas", "Endereço de Rede", "Prefixo", "Máscara de Sub-rede"]

    body =
      Enum.map(rows, fn r ->
        [Integer.to_string(r.machines), r.addr, "/#{r.prefix}", r.mask]
      end)

    table =
      body
      |> TableRex.Table.new(header, title)
      |> TableRex.Table.put_column_meta(:all, align: :center)

    IO.puts(TableRex.Table.render!(table))
  end

  defp print_json(data) do
    case Jason.encode(data) do
      {:ok, s} -> IO.puts(s)
      {:error, e} -> print_error("falha ao gerar JSON: #{Exception.message(e)}")
    end
  end

  defp print_error(msg), do: IO.puts(:stderr, "Erro: #{msg}")

  defp print_usage do
    IO.puts("\nUso:")
    IO.puts("  mix weaver                   # modo interativo")
    IO.puts("  mix weaver [opções]          # modo não-interativo")

    IO.puts("\nOpções:")
    IO.puts("  -h, --help                  Mostrar esta ajuda")
    IO.puts("  -H, --hosts \"500,100,100\"   Lista de hosts por rede (CSV ou espaço)")

    IO.puts("  -m, --mode MODE             fixed | separated | sequential | all (padrão: all)")

    IO.puts("  -f, --format FORMAT         table | json (padrão: table)")

    IO.puts("\nExemplos:")
    IO.puts("  mix weaver -H 500,100,100 -m all -f table")
    IO.puts("  mix weaver -H \"500 100 100\" -m sequential --format json")
  end
end
