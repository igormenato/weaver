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
  def run(args) do
    Weaver.CLI.main(args)
  end
end
