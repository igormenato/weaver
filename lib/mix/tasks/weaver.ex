defmodule Mix.Tasks.Weaver do
  use Mix.Task

  @shortdoc "Calcular endereçamento IPv4 (3 modos)"

  @moduledoc """
  Chama `Weaver.CLI` com os mesmos argumentos de `mix weaver`.
  """

  @impl Mix.Task
  def run(args) do
    Weaver.CLI.main(args)
  end
end
