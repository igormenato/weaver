defmodule Weaver.Socket.Listener do
  @moduledoc """
  TCP listener that accepts incoming connections and spawns a session
  task for each one using `Weaver.Socket.TaskSupervisor`.

  Supports connection limiting via `:max_connections` option to prevent DoS.
  """
  use GenServer

  require Logger
  alias Weaver.Socket.Session
  alias Weaver.Socket.TaskSupervisor, as: SocketTaskSupervisor

  @default_opts [backlog: 1024, max_connections: 100]

  # Public API
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, any()}
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  @spec get_port(atom() | pid()) :: non_neg_integer()
  def get_port(server \\ __MODULE__) do
    GenServer.call(server, :port)
  end

  @spec get_host(atom() | pid()) :: String.t()
  def get_host(server \\ __MODULE__) do
    GenServer.call(server, :host)
  end

  # Callbacks
  @impl true
  def init(given_opts) do
    # Priority: CLI args (given_opts) > config > module defaults
    app_config = Application.get_env(:weaver, Weaver.Socket, []) || []

    opts =
      @default_opts
      |> Keyword.merge(app_config)
      |> Keyword.merge(given_opts)

    # Fetch with defaults if not present after merge
    host = Keyword.get(opts, :host, "0.0.0.0")
    port = Keyword.get(opts, :port, 4040)
    backlog = Keyword.get(opts, :backlog, 1024)
    max_connections = Keyword.get(opts, :max_connections, 100)

    ip_tuple = parse_ip(host)

    listen_opts = [
      :binary,
      packet: :line,
      active: false,
      reuseaddr: true,
      backlog: backlog,
      ip: ip_tuple
    ]

    case :gen_tcp.listen(port, listen_opts) do
      {:ok, lsock} ->
        Logger.info("Weaver.Socket.Listener started on #{host}:#{port}")
        {:ok, accept_pid} = Task.start(fn -> accept_loop(lsock, max_connections) end)

        {:ok,
         %{
           listen: lsock,
           accept_pid: accept_pid,
           max_connections: max_connections
         }}

      {:error, reason} ->
        Logger.error("Failed to start listener: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:port, _from, state) do
    {:ok, {_ip, port}} = :inet.sockname(state.listen)
    {:reply, port, state}
  end

  @impl true
  def handle_call(:host, _from, state) do
    {:ok, {ip, _port}} = :inet.sockname(state.listen)
    {:reply, ip_to_string(ip), state}
  end

  @impl true
  def terminate(_reason, state) do
    if Map.has_key?(state, :listen) do
      :gen_tcp.close(state.listen)
    end

    :ok
  end

  defp accept_loop(listen_socket, max_connections) do
    # Check current connection count
    case Task.Supervisor.children(SocketTaskSupervisor) |> length() do
      count when count >= max_connections ->
        Logger.warning("Max connections (#{max_connections}) reached, rejecting new connections")
        :timer.sleep(100)
        accept_loop(listen_socket, max_connections)

      _ ->
        case :gen_tcp.accept(listen_socket) do
          {:ok, socket} ->
            start_session_task(socket)
            accept_loop(listen_socket, max_connections)

          {:error, :closed} ->
            :ok

          {:error, reason} ->
            Logger.error("Accept error: #{inspect(reason)}")
            :timer.sleep(1000)
            accept_loop(listen_socket, max_connections)
        end
    end
  end

  defp start_session_task(socket) do
    case Task.Supervisor.start_child(SocketTaskSupervisor, fn ->
           Session.serve(socket)
         end) do
      {:ok, pid} ->
        :ok = :gen_tcp.controlling_process(socket, pid)
        :ok

      {:error, reason} ->
        Logger.error("Failed to start socket task: #{inspect(reason)}")
    end
  end

  defp parse_ip(host) when is_binary(host) do
    case :inet.parse_address(to_charlist(host)) do
      {:ok, ip} ->
        ip

      {:error, reason} ->
        Logger.warning(
          "Invalid IP address '#{host}': #{inspect(reason)}, falling back to 0.0.0.0"
        )

        {0, 0, 0, 0}
    end
  end

  defp ip_to_string(ip) do
    to_string(:inet.ntoa(ip))
  end
end
