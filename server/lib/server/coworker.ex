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
  `builder` here and a `reviewer` in the next workspace. `lead?` is derived once, by `lead/1`, so
  every caller agrees on who leads.

  Not to be confused with `Server.Staff.roster/0`, the IN FLIGHT list of live sessions. A bench is
  who a workspace employs; that roster is who is on the clock.
  """

  # Only the NAME is enforced: it is the identity (the handle, the window, the agent's own name).
  # `agent_id` is the DB pointer and is absent in a pure render fixture, which has no DB.
  @enforce_keys [:name]
  defstruct [
    :id,
    :agent_id,
    :name,
    :archetype,
    :sort,
    :grade,
    :specialty,
    :persona,
    crew: "all",
    lead?: false
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          agent_id: integer() | nil,
          name: String.t(),
          archetype: String.t() | nil,
          sort: integer() | nil,
          grade: String.t() | nil,
          specialty: String.t() | nil,
          crew: String.t(),
          persona: map() | nil,
          lead?: boolean()
        }

  @statuses [:working, :waiting, :idle, :off, :cold]

  @glyphs %{working: "●", waiting: "!", idle: "○", off: "·", cold: "◌"}

  @doc """
  The bench's lead — its first `builder`, the default worker, else its first seat. Better a
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

  @type status :: :working | :waiting | :idle | :off | :cold

  @doc "Every status, in the order a surface lists them."
  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @doc "The one glyph a text surface draws for a status."
  @spec glyph(status()) :: String.t()
  def glyph(status), do: Map.fetch!(@glyphs, status)

  @doc """
  The one answer to "what is this seat doing", from facts the roster and the office already hold:
  `on_shift` (its crew is on, `Server.Shifts`), `session` (a registered live session), `windowed` (a
  tmux window runs it), `warm` (that window and a session warm enough to wake), `thinking` (mid-turn,
  `Server.Presence.Thinking`) and `waiting` (it leads a thread that waits on the operator: a pane
  prompt or an ask).

    * `:off` — its crew is off shift, or nothing runs it: no session, no window;
    * `:waiting` — waiting on the operator (outranks mid-turn: the turn is stuck on the answer);
    * `:working` — mid-turn;
    * `:idle` — a window it can be woken in (warm);
    * `:cold` — a session whose window is gone or whose warmth has run out, or a window with no session behind it: the next wake rotates it onto a fresh one.
  """
  @spec status(%{
          on_shift: boolean(),
          session: boolean(),
          windowed: boolean(),
          warm: boolean(),
          thinking: boolean(),
          waiting: boolean()
        }) :: status()
  def status(%{on_shift: false}), do: :off
  def status(%{session: false, windowed: false}), do: :off
  def status(%{waiting: true}), do: :waiting
  def status(%{thinking: true}), do: :working
  def status(%{warm: true}), do: :idle

  def status(_facts), do: :cold

  @doc "One roster row (`Server.Office.status/0`) as the line `tlon-cli roster` prints."
  @spec roster_line(map()) :: String.t()
  def roster_line(%{status: status, agent: agent, thread_id: tid, title: title} = row) do
    pane = if row[:pane_ref], do: " [#{row.pane_ref}]", else: ""
    "#{glyph(status)} #{agent} #{status} — ##{tid} #{title}#{pane}"
  end
end
