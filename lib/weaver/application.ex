defmodule Weaver.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      {Task.Supervisor, name: Weaver.Socket.TaskSupervisor},
      {Weaver.Socket.Listener, []}
    ]

    opts = [strategy: :one_for_one, name: Weaver.Supervisor]
    children = children
    Supervisor.start_link(children, opts)
  end

  # HTTP wrapper removed; no optional children are added.
    # No optional HTTP child anymore (Cowboy removed)
end
