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
end
