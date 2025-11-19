defmodule Weaver.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    argv = System.argv()

    # For escript mode, only start supervision if --serve flag is present
    # Otherwise, return without starting supervision (let CLI handle it)
    if "--serve" in argv do
      {opts, _args, _invalid} = Weaver.CLI.parse_args(argv)
      listener_opts = build_listener_opts(opts)

      children = [
        {Task.Supervisor, name: Weaver.Socket.TaskSupervisor},
        {Weaver.Socket.Listener, listener_opts}
      ]

      opts = [strategy: :one_for_one, name: Weaver.Supervisor]
      Supervisor.start_link(children, opts)
    else
      # Non-serve mode: Don't start supervision tree, return empty supervisor
      # CLI will be invoked separately by escript main
      Supervisor.start_link([], strategy: :one_for_one, name: Weaver.Supervisor)
    end
  end

  defp build_listener_opts(parsed_opts) do
    host = Keyword.get(parsed_opts, :socket_host)
    port = Keyword.get(parsed_opts, :socket_port)

    []
    |> maybe_put(:host, host)
    |> maybe_put(:port, port)
  end

  defp maybe_put(keyword, _key, nil), do: keyword
  defp maybe_put(keyword, key, value), do: Keyword.put(keyword, key, value)
end
