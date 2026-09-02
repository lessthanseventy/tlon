defmodule Mix.Tasks.Server.PromoteFact do
  @shortdoc "Promote a banked fact into the wipe-proof seed so it survives a DB reset"

  @moduledoc """
  #{@shortdoc}.

  A session-banked fact lives in the DB and dies on the next wipe. Promoting it appends a seed-entry
  to `priv/seed/promoted_facts.exs`, which `Server.Seed` merges with the curated
  `repo_knowledge.exs` on every boot — so the learning is re-banked into every fresh world. The loop
  that lets Tlön's bootstrap knowledge accumulate instead of resetting to a fixed baseline.

  Idempotent, keyed by `intent`. The intent is the fact's own `intent` if set, else a generated
  `seed:promoted:<id>`; override it with `--intent`.

      TLON_DB=.dev/tlon.db mix server.promote_fact 42
      TLON_DB=.dev/tlon.db mix server.promote_fact 42 --intent seed:coworker-warmth-window
  """
  use Mix.Task
  use Boundary, classify_to: Server

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {opts, positional, _} = OptionParser.parse(argv, strict: [intent: :string])

    case positional do
      [id_str | _] ->
        promote(id_str, opts[:intent])

      [] ->
        Mix.raise("usage: mix server.promote_fact <fact_id> [--intent seed:slug]")
    end
  end

  defp promote(id_str, intent) do
    id = String.to_integer(id_str)

    case Server.Seed.promote_fact(id, intent) do
      {:ok, key, count} ->
        Mix.shell().info("server.promote_fact: promoted fact ##{id} as #{key} (#{count} promoted fact(s) total).")

      {:error, :no_fact} ->
        Mix.raise("server.promote_fact: no fact ##{id}")
    end
  end
end
