import Config

config :weaver, Weaver.Socket,
  host: "0.0.0.0",
  port: 4040,
  max_connections: 100,
  max_request_length: 65_536,
  max_hosts: 1024,
  max_host_value: 65_535,
  read_timeout_ms: 5_000
