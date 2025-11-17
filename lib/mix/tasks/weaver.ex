defmodule Mix.Tasks.Weaver do
  use Mix.Task
  alias Weaver.Socket.{Client, Listener}

  @shortdoc "Calcular endereçamento IPv4 (3 modos)"

  @moduledoc """
  Task interativa para calcular endereçamento para uma topologia a partir do número
  de redes e hosts por rede. Imprime três modos:

  1) Fixo /16 e /24
  2) VLSM com endereços separados
  3) VLSM com endereços sequenciais
  """

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = parse_args(args)

    cond do
      Keyword.get(opts, :help, false) ->
        print_usage()
        :ok

      Keyword.get(opts, :serve, false) ->
        serve_opts = build_serve_opts(opts)
        start_dev_server(serve_opts)

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
        help: :boolean,
        serve: :boolean,
        socket_host: :string,
        socket_port: :integer
      ],
      aliases: [H: :hosts, m: :mode, f: :format, h: :help]
    )
  end

  defp build_serve_opts(opts) do
    host = Keyword.get(opts, :socket_host, nil)
    port = Keyword.get(opts, :socket_port, nil)

    serve_opts = []
    serve_opts = if host, do: Keyword.put(serve_opts, :host, host), else: serve_opts
    serve_opts = if port, do: Keyword.put(serve_opts, :port, port), else: serve_opts

    serve_opts
  end

  defp start_dev_server(serve_opts) do
    start_task_supervisor_if_needed()

    case Listener.start_link(serve_opts) do
      {:ok, _pid} ->
        Mix.shell().info(
          "Weaver socket server started on #{Keyword.get(serve_opts, :host, "127.0.0.1")}:#{Keyword.get(serve_opts, :port, 4040)}"
        )

        receive do
          :stop -> :ok
        end

      {:error, reason} ->
        Mix.shell().error("Failed to start server: #{inspect(reason)}")
    end
  end

  defp start_task_supervisor_if_needed do
    if Process.whereis(Weaver.Socket.TaskSupervisor) == nil do
      case Task.Supervisor.start_link(name: Weaver.Socket.TaskSupervisor) do
        {:ok, _} ->
          :ok

        {:error, {:already_started, _}} ->
          :ok

        {:error, reason} ->
          Mix.shell().error("Failed to start TaskSupervisor: #{inspect(reason)}")
      end
    end
  end

  defp handle_hosts(opts, hosts_csv) do
    machines =
      hosts_csv
      |> String.split([",", " "], trim: true)
      |> Enum.map(&String.to_integer/1)

    mode = Keyword.get(opts, :mode, "all")
    format = String.downcase(Keyword.get(opts, :format, "table"))

    socket_host = Keyword.get(opts, :socket_host)
    socket_port = Keyword.get(opts, :socket_port)

    if socket_host || socket_port do
      host = socket_host || "127.0.0.1"
      port = socket_port || 4040
      run_client_request(host, port, machines, mode, format)
    else
      run_non_interactive(machines, mode, format)
    end
  end

  defp run_client_request(host, port, machines, mode, format) do
    request = %{"hosts" => machines, "mode" => mode}

    case Client.call(host, port, request) do
      {:ok, %{"status" => "ok", "data" => data}} ->
        handle_server_response(data, mode, format)

      {:error, {code, msg}} ->
        Mix.shell().error("Server error (#{code}): #{msg}")

      {:error, reason} ->
        Mix.shell().error("Error connecting to server: #{inspect(reason)}")
    end
  end

  defp handle_server_response(data, mode, format) do
    format_down = String.downcase(format)
    mode_down = String.downcase(mode)

    if format_down == "json" do
      print_json(data)
    else
      cond do
        mode_down == "all" and is_map(data) -> render_outputs_map_mode(data, format)
        is_list(data) -> render_outputs_list_mode(data, mode, format)
        true -> Mix.shell().error("Server sent unsupported data format")
      end
    end
  end

  defp run_interactive do
    Mix.shell().info("Quantas redes?")
    n = read_int!()

    machines =
      1..n
      |> Enum.map(fn i ->
        Mix.shell().info("Quantas máquinas na rede #{i}?")
        read_int!()
      end)

    render_outputs(machines, "all", "table")
  end

  defp run_non_interactive(machines, mode, format) do
    render_outputs(machines, mode, format)
  end

  defp render_outputs(machines, mode, format) do
    with {:ok, fixed} <- safe(fn -> Weaver.fixed_masks(machines) end),
         {:ok, sep} <- safe(fn -> Weaver.vlsm_separated(machines) end),
         {:ok, seq} <- safe(fn -> Weaver.vlsm_sequential(machines) end) do
      case {String.downcase(mode), String.downcase(format)} do
        {"fixed", "json"} ->
          print_json(fixed)

        {"separated", "json"} ->
          print_json(sep)

        {"sequential", "json"} ->
          print_json(seq)

        {"all", "json"} ->
          print_json(%{fixed: fixed, separated: sep, sequential: seq})

        {"fixed", _} ->
          print_table("Modo 1 - Fixo /16 e /24", fixed)

        {"separated", _} ->
          print_table("Modo 2 - VLSM (separado)", sep)

        {"sequential", _} ->
          print_table("Modo 3 - VLSM (sequencial)", seq)

        {"all", _} ->
          print_table("Modo 1 - Fixo /16 e /24", fixed)
          print_table("Modo 2 - VLSM (separado)", sep)
          print_table("Modo 3 - VLSM (sequencial)", seq)
      end
    else
      {:error, msg} -> Mix.shell().error("Erro: #{msg}")
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

  defp render_outputs_list_mode(list, mode, format) do
    case {String.downcase(mode), String.downcase(format)} do
      {"fixed", "json"} -> print_json(list)
      {"separated", "json"} -> print_json(list)
      {"sequential", "json"} -> print_json(list)
      {"fixed", _} -> print_table("Modo 1 - Fixo /16 e /24", list)
      {"separated", _} -> print_table("Modo 2 - VLSM (separado)", list)
      {"sequential", _} -> print_table("Modo 3 - VLSM (sequencial)", list)
      _ -> Mix.shell().info("Resposta não suportada")
    end
  end

  defp render_outputs_map_mode(map, format) do
    if String.downcase(format) == "json" do
      print_json(map)
    else
      print_table("Modo 1 - Fixo /16 e /24", Map.fetch!(map, "fixed"))
      print_table("Modo 2 - VLSM (separado)", Map.fetch!(map, "separated"))
      print_table("Modo 3 - VLSM (sequencial)", Map.fetch!(map, "sequential"))
    end
  end

  defp print_table(title, rows) do
    Mix.shell().info("")
    # Normalize rows to a consistent atom-keyed map so both local and remote data work
    rows = Enum.map(rows, &normalize_row/1)
    Mix.shell().info("== #{title} ==")

    # Calcular larguras dinâmicas das colunas
    machines_strs = Enum.map(rows, &Integer.to_string(&1.machines))
    addr_strs = Enum.map(rows, & &1.addr)
    prefix_strs = Enum.map(rows, &"/#{&1.prefix}")
    mask_strs = Enum.map(rows, & &1.mask)

    width1 =
      max(String.length("Máquinas"), Enum.max([0 | Enum.map(machines_strs, &String.length/1)])) +
        2

    width2 =
      max(
        String.length("Endereço de Rede"),
        Enum.max([0 | Enum.map(addr_strs, &String.length/1)])
      ) + 2

    width3 =
      max(String.length("Prefixo"), Enum.max([0 | Enum.map(prefix_strs, &String.length/1)])) + 2

    width4 =
      max(
        String.length("Máscara de Sub-rede"),
        Enum.max([0 | Enum.map(mask_strs, &String.length/1)])
      ) + 2

    widths = [width1, width2, width3, width4]
    header_cells = ["Máquinas", "Endereço de Rede", "Prefixo", "Máscara de Sub-rede"]

    top_border = border_line(widths, {"┌", "┬", "┐"})
    mid_border = border_line(widths, {"├", "┼", "┤"})
    bottom_border = border_line(widths, {"└", "┴", "┘"})

    Mix.shell().info(top_border)
    Mix.shell().info(row_line(header_cells, widths))
    Mix.shell().info(mid_border)

    Enum.each(rows, fn r ->
      row = [Integer.to_string(r.machines), r.addr, "/#{r.prefix}", r.mask]
      Mix.shell().info(row_line(row, widths))
    end)

    Mix.shell().info(bottom_border)
  end

  defp border_line(widths, {left, mid, right}) do
    inner = Enum.map_join(widths, mid, &String.duplicate("─", &1))
    "#{left}#{inner}#{right}"
  end

  defp row_line(values, widths) do
    cells =
      Enum.map_join(Enum.zip(values, widths), "│", fn {value, width} ->
        inner_width = max(width - 2, 0)
        len = String.length(value)
        padding = max(inner_width - len, 0)
        left = div(padding, 2)
        right = padding - left
        " " <> String.duplicate(" ", left) <> value <> String.duplicate(" ", right) <> " "
      end)

    "│#{cells}│"
  end

  defp print_json(data) do
    json =
      case data do
        list when is_list(list) ->
          Enum.map(list, fn r ->
            %{
              machines: Map.get(r, :machines) || Map.get(r, "machines"),
              addr: Map.get(r, :addr) || Map.get(r, "addr"),
              prefix: Map.get(r, :prefix) || Map.get(r, "prefix"),
              mask: Map.get(r, :mask) || Map.get(r, "mask")
            }
          end)

        map when is_map(map) ->
          map
      end

    case Jason.encode(json) do
      {:ok, s} -> IO.puts(s)
      {:error, e} -> Mix.shell().error("Erro ao gerar JSON: #{Exception.message(e)}")
    end
  end

  defp normalize_row(row) when is_map(row) do
    %{
      machines: Map.get(row, :machines) || Map.get(row, "machines"),
      addr: Map.get(row, :addr) || Map.get(row, "addr"),
      prefix: Map.get(row, :prefix) || Map.get(row, "prefix"),
      mask: Map.get(row, :mask) || Map.get(row, "mask")
    }
  end

  defp print_usage do
    Mix.shell().info("\nUso:")
    Mix.shell().info("  mix weaver                   # modo interativo")
    Mix.shell().info("  mix weaver [opções]          # modo não-interativo")

    Mix.shell().info("\nOpções:")
    Mix.shell().info("  -h, --help                  Mostrar esta ajuda")
    Mix.shell().info("  -H, --hosts \"500,100,100\"   Lista de hosts por rede (CSV ou espaço)")

    Mix.shell().info(
      "  -m, --mode MODE             fixed | separated | sequential | all (padrão: all)"
    )

    Mix.shell().info("  -f, --format FORMAT         table | json (padrão: table)")
    Mix.shell().info("  --serve                     Startar servidor TCP JSON (dev)")
    Mix.shell().info("  --socket-host HOST          Host do servidor TCP (cliente)")
    Mix.shell().info("  --socket-port PORT          Porta do servidor TCP (cliente)")

    Mix.shell().info("\nExemplos:")
    Mix.shell().info("  mix weaver -H 500,100,100 -m all -f table")
    Mix.shell().info("  mix weaver -H \"500 100 100\" -m sequential --format json")
  end

  defp safe(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    e in [ArgumentError] -> {:error, e.message}
    e -> {:error, Exception.message(e)}
  end
end
