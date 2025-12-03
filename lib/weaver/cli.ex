defmodule Weaver.CLI do
  @moduledoc """
  Handles command-line arguments for the Weaver application in release mode.
  """
  alias Weaver.Socket.{Client, Listener}

  def main(args) do
    {opts, _rest, _invalid} = parse_args(args)

    cond do
      Keyword.get(opts, :help, false) ->
        print_usage()

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

  def parse_args(args) do
    OptionParser.parse(args,
      switches: [
        hosts: :string,
        mode: :string,
        format: :string,
        help: :boolean,
        serve: :boolean,
        socket_host: :string,
        socket_port: :integer,
        socket_user: :string,
        socket_password: :string
      ],
      aliases: [H: :hosts, m: :mode, f: :format, h: :help]
    )
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
    socket_user = Keyword.get(opts, :socket_user)
    socket_password = Keyword.get(opts, :socket_password)

    if socket_host || socket_port do
      host = socket_host || "127.0.0.1"
      port = socket_port || 4040

      client_opts = [
        user: socket_user,
        password: socket_password
      ]

      run_client_request(host, port, machines, mode, format, client_opts)
    else
      run_non_interactive(machines, mode, format)
    end
  end

  defp run_client_request(host, port, machines, mode, format, client_opts) do
    request = %{"hosts" => machines, "mode" => mode}

    case Client.call(host, port, request, client_opts) do
      {:ok, %{"status" => "ok", "data" => data}} ->
        handle_server_response(data, mode, format)

      {:error, {code, msg}} ->
        IO.puts(:stderr, "Server error (#{code}): #{msg}")

      {:error, reason} ->
        IO.puts(:stderr, "Error connecting to server: #{inspect(reason)}")
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
        true -> IO.puts(:stderr, "Server sent unsupported data format")
      end
    end
  end

  defp run_interactive do
    IO.puts("Quantas redes?")
    n = read_int!()

    machines =
      1..n
      |> Enum.map(fn i ->
        IO.puts("Quantas máquinas na rede #{i}?")
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
      {:error, msg} -> IO.puts(:stderr, "Erro: #{msg}")
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
            IO.puts(:stderr, "Digite um inteiro positivo.")
            read_int!()
        end
    end
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
    case Listener.start_link(serve_opts) do
      {:ok, _pid} ->
        host = Listener.get_host()
        port = Listener.get_port()

        IO.puts("Weaver socket server started on #{host}:#{port}")
        IO.puts("Press Ctrl+C to stop")

        Process.sleep(:infinity)

      {:error, {:already_started, _}} ->
        # Listener already started by Application supervision tree
        host = Listener.get_host()
        port = Listener.get_port()
        IO.puts("Weaver socket server started on #{host}:#{port}")
        IO.puts("Press Ctrl+C to stop")
        Process.sleep(:infinity)

      {:error, reason} ->
        IO.puts(:stderr, "Failed to start server: #{inspect(reason)}")
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
      _ -> IO.puts("Resposta não suportada")
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
    IO.puts("")
    rows = Enum.map(rows, &normalize_row/1)
    IO.puts("== #{title} ==")

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

    IO.puts(top_border)
    IO.puts(row_line(header_cells, widths))
    IO.puts(mid_border)

    Enum.each(rows, fn r ->
      row = [Integer.to_string(r.machines), r.addr, "/#{r.prefix}", r.mask]
      IO.puts(row_line(row, widths))
    end)

    IO.puts(bottom_border)
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
      {:error, e} -> IO.puts(:stderr, "Erro ao gerar JSON: #{Exception.message(e)}")
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
    IO.puts("\nUso:")
    IO.puts("  [binary]                     # modo interativo")
    IO.puts("  [binary] [opções]            # modo não-interativo")

    IO.puts("\nOpções:")
    IO.puts("  -h, --help                  Mostrar esta ajuda")
    IO.puts("  -H, --hosts \"500,100,100\"   Lista de hosts por rede (CSV ou espaço)")

    IO.puts("  -m, --mode MODE             fixed | separated | sequential | all (padrão: all)")

    IO.puts("  -f, --format FORMAT         table | json (padrão: table)")
    IO.puts("  --serve                     Startar servidor TCP JSON (dev)")
    IO.puts("  --socket-host HOST          Host do servidor TCP (cliente)")
    IO.puts("  --socket-port PORT          Porta do servidor TCP (cliente)")
    IO.puts("  --socket-user USER          Usuário para autenticação")
    IO.puts("  --socket-password PASS      Senha para autenticação")

    IO.puts("\nExemplos:")
    IO.puts("  [binary] -H 500,100,100 -m all -f table")
    IO.puts("  [binary] -H \"500 100 100\" -m sequential --format json")

    IO.puts(
      "  [binary] -H 500,100 --socket-host 127.0.0.1 --socket-user admin --socket-password secret"
    )
  end

  defp safe(fun) when is_function(fun, 0) do
    {:ok, fun.()}
  rescue
    e in [ArgumentError] -> {:error, e.message}
    e -> {:error, Exception.message(e)}
  end
end
