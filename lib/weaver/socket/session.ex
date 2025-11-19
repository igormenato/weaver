defmodule Weaver.Socket.Session do
  @moduledoc false
  require Logger

  @default_timeout 5_000

  @spec serve(port() | :gen_tcp.socket()) :: :ok
  def serve(socket) do
    opts = session_opts()

    case :gen_tcp.recv(socket, 0, opts.timeout) do
      {:ok, data} ->
        process_recv_ok(socket, data, opts)

      {:error, reason} ->
        handle_recv_error(socket, reason)
    end
  end

  defp handle_recv_error(socket, :timeout),
    do: send_error(socket, :timeout, "timeout waiting for request")

  defp handle_recv_error(_socket, :closed), do: :ok

  defp handle_recv_error(socket, reason) do
    Logger.error("recv error: #{inspect(reason)}")
    send_error(socket, :recv_error, "recv error: #{inspect(reason)}")
  end

  defp handle_request(socket, data, max_hosts, max_host_value) do
    json = String.trim(data)

    with {:ok, request} <- decode(json),
         :ok <- validate_request(request, max_hosts, max_host_value) do
      case do_dispatch(request) do
        {:ok, response} -> send_response(socket, response)
        {:error, {code, message}} -> send_error(socket, code, message)
      end
    else
      {:error, {code, message}} -> send_error(socket, code, message)
    end
  end

  defp decode(s) do
    case Jason.decode(s) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, {:invalid_json, "invalid JSON payload"}}
      {:error, reason} -> {:error, {:invalid_json, Exception.message(reason)}}
    end
  rescue
    e -> {:error, {:invalid_json, Exception.message(e)}}
  end

  defp validate_request(%{"hosts" => hosts}, max_hosts, max_host_value) when is_list(hosts) do
    cond do
      hosts == [] ->
        {:error, {:hosts_empty, "hosts list must not be empty"}}

      length(hosts) > max_hosts ->
        {:error, {:hosts_too_long, "hosts list too long"}}

      not Enum.all?(hosts, fn h -> is_integer(h) and h > 0 and h <= max_host_value end) ->
        {:error,
         {:hosts_value_out_of_range,
          "hosts must be a list of positive integers within allowable range"}}

      true ->
        :ok
    end
  end

  defp validate_request(_, _, _), do: {:error, {:missing_hosts, "missing required 'hosts' field"}}

  defp do_dispatch(request) do
    hosts = request["hosts"]
    mode = (request["mode"] || "all") |> String.downcase()

    dispatch_mode(mode, hosts)
  end

  defp dispatch_mode("fixed", hosts), do: safe_fixed(hosts)
  defp dispatch_mode("separated", hosts), do: safe_vlsm_separated(hosts)
  defp dispatch_mode("sequential", hosts), do: safe_vlsm_sequential(hosts)

  defp dispatch_mode("all", hosts) do
    fixed = safe_fixed(hosts)
    sep = safe_vlsm_separated(hosts)
    seq = safe_vlsm_sequential(hosts)

    case {fixed, sep, seq} do
      {{:ok, f}, {:ok, s}, {:ok, q}} -> {:ok, %{fixed: f, separated: s, sequential: q}}
      {{:error, msg}, _, _} -> {:error, msg}
      {_, {:error, msg}, _} -> {:error, msg}
      {_, _, {:error, msg}} -> {:error, msg}
    end
  end

  defp dispatch_mode(_unknown, _hosts), do: {:error, {:invalid_mode, "invalid mode"}}

  defp safe_fixed(hosts) do
    {:ok, Weaver.fixed_masks(hosts)}
  rescue
    e in [ArgumentError] -> {:error, {:dispatch_error, e.message}}
    e -> {:error, {:dispatch_error, Exception.message(e)}}
  end

  defp safe_vlsm_separated(hosts) do
    {:ok, Weaver.vlsm_separated(hosts)}
  rescue
    e in [ArgumentError] -> {:error, {:dispatch_error, e.message}}
    e -> {:error, {:dispatch_error, Exception.message(e)}}
  end

  defp safe_vlsm_sequential(hosts) do
    {:ok, Weaver.vlsm_sequential(hosts)}
  rescue
    e in [ArgumentError] -> {:error, {:dispatch_error, e.message}}
    e -> {:error, {:dispatch_error, Exception.message(e)}}
  end

  defp send_response(socket, data) do
    payload = Jason.encode!(%{status: "ok", data: data})
    :ok = :gen_tcp.send(socket, payload <> "\n")
    :gen_tcp.close(socket)
  end

  defp send_error(socket, code, message) do
    payload = Jason.encode!(%{status: "error", code: to_string(code), message: message})
    :gen_tcp.send(socket, payload <> "\n")
    :gen_tcp.close(socket)
  end

  defp session_opts do
    opts = Application.get_env(:weaver, Weaver.Socket, []) || []

    %{
      timeout: opts[:read_timeout_ms] || @default_timeout,
      max_request_length: opts[:max_request_length] || 65_536,
      max_hosts: opts[:max_hosts] || 1024,
      max_host_value: opts[:max_host_value] || 65_535
    }
  end

  defp process_recv_ok(socket, data, opts) do
    if byte_size(data) > opts.max_request_length do
      send_error(socket, :payload_too_large, "payload too large")
    else
      handle_request(socket, data, opts.max_hosts, opts.max_host_value)
    end
  end
end
