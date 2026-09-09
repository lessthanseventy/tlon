defmodule Server.Coworker do
  @moduledoc """
  One seat on a workspace's BENCH: the coworkers it employs, standing whether or not any of them
  is running right now (UX slice 5). The boundary type the roster read hands out, in place of the
  raw `%{"archetype" => _, "name" => _}` maps eight modules used to each interpret for themselves.

  **`name` is the handle AND the tmux window name.** There is no transformation, and that is the
  point: the old model kept the agent as `"<name>-machine"` while mentions, windows and the
  profile registry used the bare `<name>`, so eight modules independently appended or stripped
  `-machine` and any one of them could drift. One name, one author.

  `archetype` lives on the seat rather than on the agent because the same coworker can be a
  `builder` here and a `reviewer` in the next workspace. `lead?` is derived once, by `lead/1` —
  it used to be derived twice, by `Server.Channel` (first builder, else first) and
  `Console.Space` (just the first), which are not the same rule and did not always agree.

  Not to be confused with `Server.Staff.roster/0`, the IN FLIGHT list of live sessions. A bench is
  who a workspace employs; that roster is who is on the clock.
  """

  # Only the NAME is enforced: it is the identity (the handle, the window, the agent's own name).
  # `agent_id` is the DB pointer and is absent in a pure render fixture, which has no DB.
  @enforce_keys [:name]
  defstruct [:id, :agent_id, :name, :archetype, :sort, lead?: false]

  @type t :: %__MODULE__{
          id: integer() | nil,
          agent_id: integer() | nil,
          name: String.t(),
          archetype: String.t() | nil,
          sort: integer() | nil,
          lead?: boolean()
        }

  @doc """
  The bench's lead — its first `builder` (the manager archetype), else its first seat. Better a
  lead than none: a workspace whose bench is staffed but whose archetypes are all unusual still
  has someone to address. `nil` for an empty bench.
  """
  @spec lead([t()]) :: t() | nil
  def lead(bench) when is_list(bench), do: Enum.find(bench, &(&1.archetype == "builder")) || List.first(bench)

  def lead(_bench), do: nil

  @doc "Stamp `lead?` on the one seat `lead/1` picks — so a consumer never re-derives the rule."
  @spec mark_lead([t()]) :: [t()]
  def mark_lead(bench) do
    case lead(bench) do
      nil -> bench
      %__MODULE__{agent_id: id} -> Enum.map(bench, &%{&1 | lead?: &1.agent_id == id})
    end
  end

  @doc """
  The wire shape for the MCP brief and anything else that speaks JSON. String-keyed, and it keeps
  `archetype`/`name` where they always were so an agent's existing reading of a workspace brief
  does not change under it.
  """
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = c),
    do: %{"agent_id" => c.agent_id, "name" => c.name, "archetype" => c.archetype, "lead" => c.lead?}
end
