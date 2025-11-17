defmodule Mix.Tasks.Weaver.SocketTest do
  use ExUnit.Case
  import ExUnit.CaptureIO
  alias Mix.Tasks.Weaver, as: WeaverTask
  alias Weaver.Socket.Listener

  test "mix task uses socket client when socket-host/port provided" do
    {:ok, _pid} =
      start_supervised({Listener, [port: 0, name: :weaver_cli_test_listener]})

    port = Listener.get_port(:weaver_cli_test_listener)

    args = [
      "--hosts",
      "500,100",
      "--socket-host",
      "127.0.0.1",
      "--socket-port",
      Integer.to_string(port),
      "--format",
      "json"
    ]

    output = capture_io(fn -> WeaverTask.run(args) end)
    assert output =~ "{"
  end
end
