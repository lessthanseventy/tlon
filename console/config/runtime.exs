import Config

# Resolve funes' SQLite path the SAME way funes' own config/runtime.exs does, so the cockpit
# and the human's `mise run funes:*` tasks read and write ONE file. Precedence:
#   1. TLON_DB (aleph's mise tasks export the repo-local .dev DB here)
#   2. $XDG_DATA_HOME/funes/wb.db, else ~/.local/share/funes/wb.db
# Skipped under :test (aleph tests keep funes' Repo down — see config/test.exs).
# Which brain (docs/plans/2026-09-08-one-brain-client-server-plan.md): `TLON_BACKEND=remote`
# makes the cockpit a client of the always-up server node (`TLON_NODE`, default the release's
# funes@127.0.0.1) over distribution; the embedded :server app then starts nothing but PubSub.
# `local` (today's default until plan A phase 4) embeds the server on TLON_DB as before.
remote? = System.get_env("TLON_BACKEND", "local") == "remote"

if config_env() != :test do
  config :console, backend: if(remote?, do: Console.Backend.Remote, else: Console.Backend.Local)
  config :console, server_node: String.to_atom(System.get_env("TLON_NODE", "funes@127.0.0.1"))

  if remote? do
    config :server, start_repo: false, bootstrap: false, start_switchboard: false, start_mcp: false
  end
end

if config_env() != :test and not remote? do
  database =
    System.get_env("TLON_DB") ||
      Path.join([
        System.get_env("XDG_DATA_HOME") ||
          Path.join(System.get_env("HOME") || ".", ".local/share"),
        "funes",
        "wb.db"
      ])

  File.mkdir_p!(Path.dirname(database))
  config :server, Server.Repo, database: database
  config :server, maintain: System.get_env("TLON_MAINTAIN") in ~w(1 true yes)

  # Mirror funes' own runtime flags: a dependency's config/*.exs is NOT evaluated when aleph
  # is the root app, so without these the memory pass / maintain monitor / workline root are
  # silently unreachable for aleph-embedded funes (the 4041 node).
  config :server, memory_pass: System.get_env("TLON_MEMORY_PASS") in ~w(1 true yes)

  if workline_root = System.get_env("TLON_WORKLINE_ROOT") do
    config :server, workline_root: workline_root
  end
end
