defmodule Mix.Tasks.Server.Seed do
  @shortdoc "Seed funes with base self-knowledge + baseline projects (idempotent)"

  @moduledoc """
  #{@shortdoc}.

  Applies `priv/seed/repo_knowledge.exs` through `Server.Seed` against `TLON_DB`: banks the base
  FACTS the repo should already know about itself and ensures the baseline PROJECTS. Idempotent —
  facts key on `intent`, projects on (workspace, name) — so a re-run only fills gaps.

  This is the manual path; the same `Server.Seed.ensure/0` also runs on every boot via
  `Server.Bootstrap`, so a fresh/reset scratch DB self-heals. Run this to apply seed-file edits
  without a restart:

      TLON_DB=.dev/tlon.db mix server.seed
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @requirements ["app.start"]

  @impl Mix.Task
  def run(_argv) do
    # Bootstrap seeds the default workspace on boot; run it here too so `mix server.seed` works
    # against a brand-new DB where no workspace exists yet (projects need a home).
    Server.Bootstrap.ensure()
    %{facts: facts, projects: projects} = Server.Seed.ensure()
    Mix.shell().info("server.seed: banked #{facts} fact(s), ensured #{projects} project(s).")
  end
end
