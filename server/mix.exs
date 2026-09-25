defmodule Server.MixProject do
  use Mix.Project

  # funes — the machine-side memory and coordination layer, as an OTP application.
  # SQLite is the truth (Ecto over ecto_sqlite3); the same single file the spec
  # measured, still sqlite3-inspectable and 2am-repairable.
  def project do
    [
      app: :server,
      version: "0.1.0",
      elixir: "~> 1.18",
      # Boundary enforcement (lib/funes.ex declares the surface) — violations are compile
      # warnings, which the gate's --warnings-as-errors turns into failures.
      compilers: [:boundary] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  # The always-up channel ships as a self-contained release: it bundles ERTS, so a
  # systemd --user unit runs one absolute path with no toolchain on PATH, and it
  # hands us `bin/server eval` (migrate before boot) plus `bin/server remote`/`rpc`
  # into the LIVE node (so a shell launcher mints under the serving world's token
  # secret, Server.MCP.Secret). Built locally (`mix release`); nix packages the same
  # release.
  defp releases do
    [
      server: [
        include_executables_for: [:unix],
        applications: [server: :permanent]
      ]
    ]
  end

  # The one internal-CI gate: format, warnings-as-errors, Credo, and the suite.
  # `mix run check` (mise) and any git pre-commit hook run this same alias.
  defp aliases do
    [
      precommit: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test --warnings-as-errors"
      ]
    ]
  end

  # Test support (e.g. Server.TestDB) compiles only under :test.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Server.Application, []}
    ]
  end

  # Run the whole precommit gate (incl. `test`) in the test environment.
  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp deps do
    [
      # Compile-time module-boundary checks (lib/funes.ex). runtime: false — pure tooling.
      {:boundary, "~> 0.10", runtime: false},
      # Menard (github.com/lessthanseventy/menard): AST-aware source edits + introspection on
      # Sourceror; the coworkers' source verbs (Server.Source.Tools) call it — a runtime dep
      # (Andrew, 2026-09-08). Pinned by ref, never a path: a nix build sees only this checkout.
      {:menard, github: "lessthanseventy/menard", tag: "v0.3.0"},
      {:ecto_sql, "~> 3.12"},
      # Postgres is the store (one-brain piece C); ecto_sqlite3 stays ONLY for `mix server.import_sqlite`,
      # the one-shot copy of the SQLite corpus — it goes when the import has run on every box.
      {:postgrex, "~> 0.22"},
      # The web UI (one-brain piece D): Phoenix + LiveView on a second loopback Bandit listener.
      {:phoenix, "~> 1.8"},
      {:phoenix_live_view, "~> 1.2"},
      {:phoenix_html, "~> 4.3"},
      # Background work (one-brain piece E): Oban on the same Postgres.
      {:oban, "~> 2.23"},
      # Oban's notifier/peers encode with Jason (not the stdlib JSON) — the release must ship it
      # (2026-09-18: the service crash-looped on Oban.Sonar without it).
      {:jason, "~> 1.4"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:ecto_sqlite3, ">= 0.17.0"},
      # The switchboard's liveness layer (§10): PubSub fans a posted message out to
      # internal consumers. SQLite stays the truth; this only makes it live.
      {:phoenix_pubsub, "~> 2.1"},
      # The sovereign channel (pi doc §2a): funes' MCP server. Anubis owns the
      # protocol lifecycle (JSON-RPC, sessions, auth, version negotiation) so it
      # cannot drift from the MCP spec under our hands; the tools themselves stay
      # thin callers of the contexts — no mirror, one writer.
      {:anubis_mcp, "~> 2.0"},
      # Serves the StreamableHTTP plug + the /mint gateway, loopback-only. Plumbing, not
      # design — the channel's contract is MCP, whatever serves it.
      {:bandit, "~> 1.0"},
      # The plug we author the /mint gateway on (Bandit serves plugs; we route one path).
      {:plug, "~> 1.0"},
      # Static analysis, part of the precommit gate.
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # A mix format plugin: one styling authority so directive order, alias
      # shape and pipe style are never a review comment again.
      {:quokka, "~> 2.13", only: [:dev, :test], runtime: false},
      # iex> examples in @doc are formatted like the code around them
      {:doctest_formatter, "~> 0.4", only: [:dev, :test], runtime: false}
    ]
  end
end
