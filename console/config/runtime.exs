import Config

# Resolve the store the SAME way the server's own config/runtime.exs does, so the cockpit and
# the human's `mise run server:*` tasks read and write ONE database.
# Skipped under :test (aleph tests keep funes' Repo down — see config/test.exs).
# Which brain (docs/plans/2026-09-08-one-brain-client-server-plan.md): `TLON_BACKEND=remote`
# makes the cockpit a client of the always-up server node (`TLON_NODE`, default the release's
# funes@127.0.0.1) over distribution; the embedded :server app then starts nothing but PubSub.
# `local` embeds the server on TLON_DATABASE (default the service's `tlon`).
remote? = System.get_env("TLON_BACKEND", "local") == "remote"

if config_env() != :test do
  config :console, backend: if(remote?, do: Console.Backend.Remote, else: Console.Backend.Local)
  config :console, server_node: String.to_atom(System.get_env("TLON_NODE", "funes@127.0.0.1"))

  if remote? do
    config :server, start_repo: false, bootstrap: false, start_switchboard: false, start_mcp: false
  end
end

if config_env() != :test and not remote? do
  # The embedded (local-backend) cockpit shares the service's store: Postgres `tlon` over the
  # socket, or TLON_DATABASE / TLON_DATABASE_URL to point elsewhere (a scratch `tlon_dev`).
  case System.get_env("TLON_DATABASE_URL") do
    nil -> config :server, Server.Repo, database: System.get_env("TLON_DATABASE") || "tlon", socket_dir: "/run/postgresql"
    url -> config :server, Server.Repo, url: url
  end

  config :server, maintain: System.get_env("TLON_MAINTAIN") in ~w(1 true yes)

  # Mirror funes' own runtime flags: a dependency's config/*.exs is NOT evaluated when aleph
  # is the root app, so without these the memory pass / maintain monitor / workline root are
  # silently unreachable for aleph-embedded funes (the 4041 node).
  config :server, memory_pass: System.get_env("TLON_MEMORY_PASS") in ~w(1 true yes)

  if workline_root = System.get_env("TLON_WORKLINE_ROOT") do
    config :server, workline_root: workline_root
  end
end
