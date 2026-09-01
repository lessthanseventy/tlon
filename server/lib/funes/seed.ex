defmodule Server.Seed do
  @moduledoc """
  Reset-safe base knowledge (2026-08-31). Loads `priv/seed/repo_knowledge.exs` — a curated set of
  FACTS the repo should already know about itself plus a baseline of PROJECTS — and applies it
  idempotently: each fact is keyed by its stable `intent`, each project by (workspace, name), so a
  re-run (a boot, a `mix server.seed`, a post-reset heal) never duplicates.

  Why it exists: a freshly-created or reset scratch DB has no self-knowledge, so funes is useless
  until someone teaches it the basics again. This bakes "some stuff about itself" into the boot path
  (`Server.Bootstrap` calls `ensure/0` after its integrity repair), and leaves the content in one
  editable file rather than scattered through code.

  An operator's manual `forget_fact` is respected: a tombstoned seed fact is NOT resurrected — the
  idempotency check is existence-by-intent, forgotten or not.
  """
  import Ecto.Query

  alias Server.Bootstrap
  alias Server.Dossier
  alias Server.Fact
  alias Server.Projects
  alias Server.Repo

  require Logger

  @seed_path "priv/seed/repo_knowledge.exs"

  @doc """
  Apply the seed: bank any missing base facts, ensure the baseline projects in the default
  workspace. Returns `%{facts: banked_count, projects: ensured_count}`. Idempotent; safe to call
  on every boot.
  """
  @spec ensure() :: %{facts: non_neg_integer(), projects: non_neg_integer()}
  def ensure do
    data = load()
    %{facts: ensure_facts(data[:facts] || []), projects: ensure_projects(data[:projects] || [])}
  end

  @doc """
  `ensure/0` for the boot path: any failure (unmigrated schema, missing seed file, repo down) is
  absorbed and logged, never allowed to take the app down — same contract as `Bootstrap.ensure_safe/0`.
  """
  @spec ensure_safe() :: %{facts: non_neg_integer(), projects: non_neg_integer()} | :skipped
  def ensure_safe do
    ensure()
  rescue
    e ->
      Logger.warning("Server.Seed: skipped — #{Exception.message(e)}")
      :skipped
  catch
    :exit, reason ->
      Logger.warning("Server.Seed: skipped — exit #{inspect(reason)}")
      :skipped
  end

  @doc "Load and evaluate the seed file into its data map (`%{facts: [...], projects: [...]}`)."
  @spec load() :: map()
  def load do
    {data, _binding} = Code.eval_file(seed_file())
    data
  end

  defp seed_file, do: Application.app_dir(:server, @seed_path)

  # Bank each fact whose `intent` isn't already present (forgotten or not — an operator's tombstone
  # is respected). Returns how many were banked this run.
  defp ensure_facts(facts) do
    Enum.count(facts, fn attrs ->
      intent = Map.fetch!(attrs, :intent)

      if fact_exists?(intent) do
        false
      else
        case Dossier.bank_fact(attrs) do
          {:ok, _fact} ->
            true

          {:error, changeset} ->
            Logger.warning("Server.Seed: fact #{inspect(intent)} rejected — #{inspect(changeset.errors)}")
            false
        end
      end
    end)
  end

  defp fact_exists?(intent), do: Repo.exists?(from f in Fact, where: f.intent == ^intent)

  # Ensure each baseline project in the default workspace. No default workspace yet (a pre-bootstrap
  # call) → nothing to house them in, so seed nothing this run; the next boot (after Bootstrap seeds
  # the workspace) picks them up.
  defp ensure_projects(projects) do
    case Bootstrap.default_workspace_id() do
      nil ->
        0

      workspace_id ->
        Enum.count(projects, &ensure_project(workspace_id, &1))
    end
  end

  defp ensure_project(workspace_id, %{name: name} = attrs) do
    if Projects.by_name(workspace_id, name) do
      false
    else
      case Projects.register(Map.put(attrs, :workspace_id, workspace_id)) do
        {:ok, _project} ->
          true

        {:error, changeset} ->
          Logger.warning("Server.Seed: project #{inspect(name)} rejected — #{inspect(changeset.errors)}")
          false
      end
    end
  end
end
