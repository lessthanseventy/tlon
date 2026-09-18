defmodule Console.WorkspaceTemplates do
  @moduledoc """
  The **workspace-archetype registry** — nix-owned *capabilities* (compiled, like `Server.Profiles`'
  coworker archetypes, not runtime-editable). A template is the STARTER shape the author face's
  "new workspace" composes a server `workspace` row from: a `type`, default `repos`, a starter `roster` of
  coworker-archetype entries, and `knobs`. The operator names it and edits from there; the created
  row is a *composition* (server-owned, runtime-editable) — the config seam the reshape settled.

  Distinct from `Server.Profiles.@archetypes`: those template a single COWORKER; these template a
  whole WORKSPACE (which references coworker archetypes by atom in its `roster`).
  """

  # roster entries reference the coworker archetype registry (`Server.Profiles`) by atom; `name` is a
  # generic role placeholder the operator renames in the author face.
  @templates %{
    code: %{
      type: "code",
      repos: ["modules/*"],
      # A full starter crew so a fresh workspace feels alive: the orchestrator (surveyor), the lead
      # (builder), plus a reviewer + planner ready to be staffed.
      roster: [
        %{archetype: :surveyor, name: "surveyor"},
        %{archetype: :builder, name: "builder"},
        %{archetype: :reviewer, name: "reviewer"},
        %{archetype: :planner, name: "planner"}
      ],
      knobs: %{}
    },
    life: %{
      type: "life",
      repos: [],
      roster: [%{archetype: :assistant, name: "assistant"}],
      knobs: %{}
    },
    blank: %{
      type: "blank",
      repos: [],
      roster: [],
      knobs: %{}
    }
  }

  @doc "The full registry — `archetype_atom => template`."
  @spec templates() :: %{atom() => map()}
  def templates, do: @templates

  @doc "The template for one workspace archetype (raises on an unknown key)."
  @spec template(atom()) :: map()
  def template(key), do: Map.fetch!(@templates, key)

  @doc "The workspace-archetype keys."
  @spec names() :: [atom()]
  def names, do: Map.keys(@templates)

  @doc """
  A `Server.Workspaces.register/1` attrs map from a template + an operator-given `name`. The roster is
  emitted in the server WIRE shape (string-keyed maps, matching the seed roster) so it round-trips
  through the changeset unchanged; `repos` is not a column at all (UX slice 5) — `register/1` turns
  each path into a `workspace_repo` row at birth.
  """
  @spec new_workspace_attrs(atom(), String.t()) :: %{
          name: String.t(),
          type: String.t(),
          scope: String.t(),
          repos: [String.t()],
          roster: [%{String.t() => String.t()}],
          knobs: map()
        }
  def new_workspace_attrs(template_key, name) do
    t = template(template_key)

    %{
      name: name,
      type: t.type,
      scope: "machine",
      repos: t.repos,
      roster: Enum.map(t.roster, &%{"archetype" => Atom.to_string(&1.archetype), "name" => &1.name}),
      knobs: t.knobs
    }
  end
end
