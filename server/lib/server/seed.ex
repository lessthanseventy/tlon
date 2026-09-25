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

  The MACHINE seed (`machine/0`, `~/.config/tlon/seed.exs`) is the box's half: its workspaces, their
  projects and bench, and facts about its operator — written by the machine (ficciones), never kept
  in this repo. `Server.Bootstrap` registers its workspaces before it would invent a default.

  An operator's manual `forget_fact` is respected: a tombstoned seed fact is NOT resurrected — the
  idempotency check is existence-by-intent, forgotten or not.
  """
  import Ecto.Query

  alias Server.Bootstrap
  alias Server.Dossier
  alias Server.Fact
  alias Server.Projects
  alias Server.Repo
  alias Server.Workspaces

  require Logger

  @seed_path "priv/seed/repo_knowledge.exs"
  # The machine-appended companion to the hand-curated file: `mix server.promote_fact` writes here,
  # so a genuinely useful session-banked fact graduates into the wipe-proof set without hand-editing
  # (or reformatting) the curated file. `load/0` merges both. Path is app-env overridable for tests.
  @promoted_path "priv/seed/promoted_facts.exs"

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

  @doc """
  Load the seed data (`%{facts: [...], projects: [...]}`) — the curated file with the promoted
  facts and the machine seed's facts appended. A later fact sharing an `intent` is harmless (ensure_facts
  dedups by intent).
  """
  @spec load() :: map()
  def load do
    {data, _binding} = Code.eval_file(seed_file())
    Map.update(data, :facts, promoted_facts(), &(&1 ++ promoted_facts() ++ (machine()[:facts] || [])))
  end

  @doc "The machine-appended promoted facts (`[]` when the file doesn't exist yet)."
  @spec promoted_facts() :: [map()]
  def promoted_facts do
    path = promoted_file()

    if File.exists?(path) do
      {list, _binding} = Code.eval_file(path)
      list
    else
      []
    end
  end

  @doc """
  Add `fact`'s seed-entry to a `promoted` list under `intent`, idempotently — the pure core of
  `mix server.promote_fact`. A stated fact keeps `stated` provenance; anything else records `derived`
  (a promoted learning is our claim, not the owner's verbatim word). Returns the (possibly unchanged) list.
  """
  @spec promote(Fact.t(), [map()], String.t()) :: [map()]
  def promote(%Fact{} = fact, promoted, intent) when is_binary(intent) do
    if Enum.any?(promoted, &(&1[:intent] == intent)) do
      promoted
    else
      promoted ++ [%{intent: intent, kind: fact.kind, provenance: fact.provenance || "derived", text: fact.text}]
    end
  end

  @doc """
  Promote the banked fact `id` into the wipe-proof set: resolve its `intent` (explicit → the fact's
  own → a generated `seed:promoted:<id>`), append it to the promoted file idempotently, and write.
  `{:ok, intent, count}` or `{:error, :no_fact}`. The engine behind `mix server.promote_fact`.
  """
  @spec promote_fact(integer() | String.t(), String.t() | nil) ::
          {:ok, String.t(), non_neg_integer()} | {:error, :no_fact}
  def promote_fact(id, intent \\ nil) do
    case Repo.get(Fact, id) do
      nil ->
        {:error, :no_fact}

      %Fact{} = fact ->
        key = intent || fact.intent || "seed:promoted:#{id}"
        updated = promote(fact, promoted_facts(), key)
        write_promoted(updated)
        {:ok, key, length(updated)}
    end
  end

  @doc "Serialize a promoted-facts list back to its file as an evaluable Elixir literal."
  @spec write_promoted([map()]) :: :ok
  def write_promoted(list) do
    header =
      "# Machine-appended seed facts (`mix server.promote_fact`) — promoted session learnings that must\n" <>
        "# survive a DB wipe. `Server.Seed` merges these with the curated priv/seed/repo_knowledge.exs.\n" <>
        "# Hand-edits are fine; keep it an evaluable list of %{intent:, kind:, provenance:, text:} maps.\n\n"

    File.write!(promoted_file(), header <> inspect(list, pretty: true, limit: :infinity) <> "\n")
  end

  defp seed_file, do: Application.app_dir(:server, @seed_path)

  defp promoted_file,
    do: Application.get_env(:server, :promoted_facts_path) || Application.app_dir(:server, @promoted_path)

  # Bank each fact whose `intent` isn't already present (forgotten or not — an operator's tombstone
  # is respected). Returns how many were banked this run.
  defp ensure_facts(facts) do
    Enum.count(facts, fn attrs ->
      intent = Map.fetch!(attrs, :intent)
      not fact_exists?(intent) and bank_seed_fact(intent, attrs)
    end)
  end

  defp bank_seed_fact(intent, attrs) do
    case Dossier.bank_fact(attrs) do
      {:ok, _fact} ->
        true

      {:error, changeset} ->
        Logger.warning("Server.Seed: fact #{inspect(intent)} rejected — #{inspect(changeset.errors)}")
        false
    end
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

  @doc """
  The machine's own seed — this box's workspaces (repos, bench, projects) and facts about its
  operator — which stay out of this repo: the machine writes it (ficciones' flake) at
  `:machine_seed_path`. `%{}` when the file is absent or unreadable, so a fresh box still boots on
  `Bootstrap`'s default workspace.
  """
  @spec machine() :: map()
  def machine do
    path = Path.expand(Application.get_env(:server, :machine_seed_path, "~/.config/tlon/seed.exs"))

    if File.exists?(path) do
      {data, _binding} = Code.eval_file(path)
      data
    else
      %{}
    end
  rescue
    e ->
      Logger.warning("Server.Seed: machine seed skipped — #{Exception.message(e)}")
      %{}
  end

  @doc """
  Register the machine seed's missing workspaces, in file order, and any of their projects the store
  lacks. Runs before `Bootstrap` would invent a default, so the first declared workspace is the
  default. An existing workspace's bench and repos are the operator's — only missing projects are added.
  Returns how many workspaces were registered.
  """
  @spec ensure_workspaces() :: non_neg_integer()
  def ensure_workspaces do
    Enum.count(machine()[:workspaces] || [], &ensure_workspace/1)
  end

  defp ensure_workspace(%{name: name} = attrs) do
    projects = Enum.map(attrs[:projects] || [], &project_attrs/1)

    {registered?, workspace} =
      case Workspaces.by_name(name) do
        nil -> {true, register_workspace(attrs, projects)}
        workspace -> {false, workspace}
      end

    if workspace, do: Enum.each(projects, &ensure_project(workspace.id, &1))
    registered? and workspace != nil
  end

  defp register_workspace(attrs, projects) do
    repos = Enum.flat_map(projects, fn p -> Enum.map(p.repos, & &1["path"]) end)
    base = %{type: "code", scope: "project", roster: []}

    base
    |> Map.merge(Map.take(attrs, [:name, :type, :scope, :roster]))
    |> Map.put(:repos, repos)
    |> Workspaces.register()
    |> case do
      {:ok, workspace} ->
        workspace

      {:error, changeset} ->
        Logger.warning("Server.Seed: workspace #{inspect(attrs.name)} rejected — #{inspect(changeset.errors)}")
        nil
    end
  end

  # A project's repos are written as paths; the store keeps `%{"name", "path"}`, named by the directory.
  defp project_attrs(%{name: name} = project),
    do: %{name: name, repos: Enum.map(project[:repos] || [], &%{"name" => Path.basename(&1), "path" => &1})}
end
