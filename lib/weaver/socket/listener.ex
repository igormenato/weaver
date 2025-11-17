defmodule Weaver.Socket.Listener do
  @moduledoc """
  TCP listener that accepts incoming connections and spawns a session
  task for each one using `Weaver.Socket.TaskSupervisor`.
  """
  use GenServer

  require Logger
  alias Weaver.Socket.Session
  alias Weaver.Socket.TaskSupervisor, as: SocketTaskSupervisor

  @default_opts [host: "127.0.0.1", port: 4040, backlog: 1024]

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

  # Callbacks
  @impl true
  def init(opts) do
    app_opts = Application.get_env(:weaver, Weaver.Socket, []) || []
    given_opts = opts
    opts = Keyword.merge(@default_opts, app_opts)
    opts = Keyword.merge(opts, given_opts)

    host = Keyword.get(opts, :host)
    port = Keyword.get(opts, :port)
    backlog = Keyword.get(opts, :backlog)

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
        # spawn accept loop in a separate process to keep this GenServer responsive
        {:ok, accept_pid} = Task.start(fn -> accept_loop(lsock) end)
        {:ok, %{listen: lsock, accept_pid: accept_pid}}

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
  def terminate(_reason, state) do
    if Map.has_key?(state, :listen) do
      :gen_tcp.close(state.listen)
    end

    :ok
  end

  # Accept loop
  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        start_session_task(socket)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, reason} ->
        Logger.error("Accept error: #{inspect(reason)}")
        :timer.sleep(1000)
        accept_loop(listen_socket)
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
      {:ok, ip} -> ip
      _ -> {127, 0, 0, 1}
    end
  end
end
