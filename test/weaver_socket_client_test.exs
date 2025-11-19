defmodule Weaver.Socket.ClientTest do
  use ExUnit.Case
  alias Weaver.Socket.{Client, Listener}

  setup do
    start_supervised!({Task.Supervisor, name: Weaver.Socket.TaskSupervisor})
    :ok
  end

  test "client returns data from server" do
    # start listener on ephemeral port
    {:ok, _pid} = start_supervised({Listener, [port: 0, name: :weaver_test_listener]})
    port = Listener.get_port(:weaver_test_listener)

    {:ok, resp} =
      Client.call("127.0.0.1", port, %{"hosts" => [500, 100, 100], "mode" => "all"})

    assert %{"status" => "ok", "data" => data} = resp
    assert is_map(data)
    assert Map.has_key?(data, "fixed")
  end

  test "client accepts hostname like 'localhost'" do
    {:ok, _pid} = start_supervised({Listener, [port: 0, name: :weaver_test_listener_hostname]})
    port = Listener.get_port(:weaver_test_listener_hostname)

    {:ok, resp} =
      Client.call("localhost", port, %{"hosts" => [50], "mode" => "fixed"})

    assert %{"status" => "ok", "data" => data} = resp
    assert is_list(data)
  end
end
