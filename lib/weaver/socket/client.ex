defmodule Weaver.Socket.Client do
  @moduledoc """
  Minimal TCP client helper to call Weaver socket server
  using newline-delimited JSON packets.
  """
  @default_timeout 5_000

  @spec call(String.t(), pos_integer(), map(), keyword()) :: {:ok, map()} | {:error, any()}
  def call(host \\ "127.0.0.1", port \\ 4040, request \\ %{}, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    ip_tuple =
      case :inet.parse_address(to_charlist(host)) do
        {:ok, ip} -> ip
        _ -> {127, 0, 0, 1}
      end

    connect_opts = [:binary, packet: :line, active: false, reuseaddr: true, ip: ip_tuple]

    case :gen_tcp.connect(ip_tuple, port, connect_opts, timeout) do
      {:ok, socket} ->
        payload = Jason.encode!(request)
        :ok = :gen_tcp.send(socket, payload <> "\n")

        case :gen_tcp.recv(socket, 0, timeout) do
          {:ok, resp} ->
            :gen_tcp.close(socket)
            decode_response(resp)

          {:error, reason} ->
            :gen_tcp.close(socket)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_response(resp) do
    case Jason.decode(resp) do
      {:ok, %{"status" => "ok"} = map} -> {:ok, map}
      {:ok, %{"status" => "error", "code" => code, "message" => msg}} -> {:error, {code, msg}}
      {:ok, %{"status" => "error", "message" => msg}} -> {:error, {"unknown", msg}}
      {:ok, map} -> {:ok, map}
      {:error, reason} -> {:error, {:invalid_json, Exception.message(reason)}}
    end
  end
end
