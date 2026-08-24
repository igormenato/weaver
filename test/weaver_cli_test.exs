defmodule Weaver.CLITest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  test "mode fixed does not run VLSM" do
    {stdout, stderr} =
      run_cli(["--hosts", "65535", "--mode", "fixed", "--format", "json"])

    assert stderr == ""
    assert stdout =~ "172.16.0.0"
    refute stdout =~ "Erro"
  end

  test "invalid hosts print an error instead of crashing" do
    {stdout, stderr} = run_cli(["--hosts", "abc", "--mode", "fixed"])

    assert stdout == ""
    assert stderr =~ "quantidade de máquinas inválida"
  end

  test "unknown mode prints an error instead of crashing" do
    {stdout, stderr} = run_cli(["--hosts", "10", "--mode", "nope"])

    assert stdout == ""
    assert stderr =~ "modo inválido"
  end

  defp run_cli(args) do
    stderr =
      capture_io(:stderr, fn ->
        stdout = capture_io(fn -> Weaver.CLI.main(args) end)
        send(self(), {:stdout, stdout})
      end)

    assert_receive {:stdout, stdout}
    {stdout, stderr}
  end
end
