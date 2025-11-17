defmodule Weaver.Socket.SessionTest do
  use ExUnit.Case
  alias Weaver.Socket.{Client, Listener}

  test "invalid json returns error status" do
    {:ok, _} = start_supervised({Listener, [port: 0, name: :session_test_listener]})
    port = Listener.get_port(:session_test_listener)

    # Connect raw and send intentionally malformed JSON
    host = "127.0.0.1" |> to_charlist()
    opts = [:binary, packet: :line, active: false]
    {:ok, sock} = :gen_tcp.connect(host, port, opts)

    :ok = :gen_tcp.send(sock, "{bad\n")
    {:ok, resp} = :gen_tcp.recv(sock, 0, 1000)
    :gen_tcp.close(sock)
    %{"status" => "error", "code" => code, "message" => msg} = Jason.decode!(resp)
    assert code == "invalid_json"
    assert msg =~ "unexpected byte"
  end

  test "missing hosts returns error" do
    {:ok, _} = start_supervised({Listener, [port: 0, name: :session_test_listener2]})
    port = Listener.get_port(:session_test_listener2)

    {:error, {code, msg}} =
      Client.call("127.0.0.1", port, %{"mode" => "all"})

    assert code == "missing_hosts"
    assert msg =~ "missing required 'hosts'"
  end

  test "hosts too long is rejected" do
    # override config for the test
    old = Application.get_env(:weaver, Weaver.Socket, [])
    Application.put_env(:weaver, Weaver.Socket, Keyword.put(old, :max_hosts, 2))

    {:ok, _} = start_supervised({Listener, [port: 0, name: :session_test_listener3]})
    port = Listener.get_port(:session_test_listener3)

    # send 3 hosts which exceeds max_hosts 2
    {:error, {code, msg}} =
      Client.call("127.0.0.1", port, %{"hosts" => [1, 2, 3]})

    assert code == "hosts_too_long"
    assert msg =~ "hosts list too long"

    Application.put_env(:weaver, Weaver.Socket, old)
  end

  test "hosts value out of range is rejected" do
    old = Application.get_env(:weaver, Weaver.Socket, [])
    Application.put_env(:weaver, Weaver.Socket, Keyword.put(old, :max_host_value, 100))

    {:ok, _} = start_supervised({Listener, [port: 0, name: :session_test_listener4]})
    port = Listener.get_port(:session_test_listener4)

    {:error, {code, msg}} =
      Client.call("127.0.0.1", port, %{"hosts" => [1, 101]})

    assert code == "hosts_value_out_of_range"
    assert msg =~ "within allowable range"

    Application.put_env(:weaver, Weaver.Socket, old)
  end

  test "payload too large is rejected" do
    old = Application.get_env(:weaver, Weaver.Socket, [])
    Application.put_env(:weaver, Weaver.Socket, Keyword.put(old, :max_request_length, 10))

    {:ok, _} = start_supervised({Listener, [port: 0, name: :session_test_listener5]})
    port = Listener.get_port(:session_test_listener5)

    host = "127.0.0.1" |> to_charlist()
    opts = [:binary, packet: :line, active: false]
    {:ok, sock} = :gen_tcp.connect(host, port, opts)

    # create a small valid JSON but longer than 10 bytes
    :ok = :gen_tcp.send(sock, "{\"hosts\": [1]}\n")
    {:ok, resp} = :gen_tcp.recv(sock, 0, 1000)
    :gen_tcp.close(sock)
    %{"status" => "error", "code" => code, "message" => msg} = Jason.decode!(resp)
    assert code == "payload_too_large"
    assert msg =~ "payload too large"

    Application.put_env(:weaver, Weaver.Socket, old)
  end
end
