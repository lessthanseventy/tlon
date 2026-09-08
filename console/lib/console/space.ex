defmodule Console.Space do
  @moduledoc """
  A **space** is a named lens over server — *what's in the middle* and the panels around it — the
  unit the rail picks. Workspaces are the ONLY spaces (UX slice 1, task 5, 2026-09-08): one per
  server workspace (`Console.Workspaces`), keyed by the server workspace id (not a name slug), so
  `[1]` with the single seeded workspace. Home/Orbis is retired — the rail + top bar are the
  overview, the drawer's TRIAGE the rollup, and its author face lives in the drawer as CONFIG.
  Server-down yields NO spaces — server self-seeds a default workspace at boot (Server.Bootstrap),
  so no fallback Workspace is fabricated here; the cockpit's `active_key` falls to the sentinel `0`.

  A surface is a LIST of sections stacked down the center — a Workspace frames
  its Terminal with the NewThread and Tertius bands below. A section is either a bare
  panel module (its data shaped by `Console.View.data_for/2`, like the sidebars) or a
  `{panel_module, read_key}` pair whose data is the named Cockpit read verbatim — how two
  Terminal panes on one surface get distinct data. A space stays plain data either way.
  """

  alias Console.Panel.Activity
  alias Console.Panel.Crew
  alias Console.Panel.Memory
  alias Console.Panel.NewThread
  alias Console.Panel.Stack
  alias Console.Panel.Terminal
  alias Console.Panel.Tertius

  @enforce_keys [:key, :label, :surface]
  defstruct [:key, :label, :surface, :id, left: [], right: [], coworker: nil, roster: []]

  @type surface :: [module() | {module(), atom()}]
  @type t :: %__MODULE__{
          key: non_neg_integer(),
          label: String.t(),
          surface: surface(),
          # The server workspace id (Phase C1). Mirrors `key`.
          id: non_neg_integer() | nil,
          left: [module()],
          right: [module()],
          # The name of the pi coworker profile this space spawns into its center, or nil for a space
          # with no machine coworker (Console.Profiles). Tlön → "tertius".
          coworker: String.t() | nil,
          # The workspace's full roster (Phase C2/C3 drive the cast from this; carried here so callers
          # don't need a second read).
          roster: [map()]
        }

  @doc """
  The spaces the rail offers, in order — one Workspace space per server workspace
  (`Console.Workspaces.all/0`). `surface` is the center; `left`/`right` the situational sidebars.
  Reads the cached workspace list; `all/1` is the pure derivation over an explicit list (tests
  inject workspaces without the live cache).
  """
  @spec all() :: [t()]
  def all, do: all(fetch_workspaces())

  @doc "The picker derived from an explicit workspace list."
  @spec all([map()]) :: [t()]
  def all(workspaces), do: workspace_spaces(workspaces)

  # One Workspace space per server workspace. An empty list means server is genuinely down — the app
  # self-seeds a default workspace at boot (Server.Bootstrap), so no fake Workspace is fabricated
  # here (reshape slice A); the picker is empty.
  defp workspace_spaces(workspaces), do: Enum.map(workspaces, &space_from_workspace/1)

  # A Workspace space built from a server workspace (console-shaped `%{id, name, roster, ...}`). Keyed by the
  # server workspace id (Phase C1) — not a name slug — so a rename can't break the active session and
  # two workspaces can never collide on key. surface/left/right/coworker reproduce the Slice-0 Tlön
  # struct exactly; the coworker is the roster lead's name.
  defp space_from_workspace(workspace) do
    %__MODULE__{
      key: workspace.id,
      id: workspace.id,
      label: workspace.name,
      # The center thread-stack is the thread surface; a thread's live lead session shows in the
      # toggleable right session pane (Alt+digit switches tmux windows). Center = the
      # Terminal/thread-stack + the new-thread band + the permanent Tertius band below.
      surface: [{Terminal, :machine}, NewThread, Tertius],
      # The funes panels — NOW (attention/activity) · CREW · MEMORY · STACK — are the drawer's since
      # UX slice 1; `left` is kept as the space's declared set, the frame paints the Rail instead.
      left: [Activity, Crew, Memory, Stack],
      right: [],
      coworker: lead_coworker(workspace.roster),
      roster: workspace.roster
    }
  end

  # Read the cached workspaces, degrading to [] (→ an empty picker) if the cache is down mid-render.
  defp fetch_workspaces do
    Console.Workspaces.all()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  # The roster lead → center coworker: the first entry's name, tolerating string (JSON) or atom keys.
  defp lead_coworker([entry | _]), do: entry["name"] || entry[:name]
  defp lead_coworker(_), do: nil

  @doc """
  The mode predicate: is `key` a Workspace space? Replaces the ~40
  `active_key == :tlon` guards the cockpit carried pre-Phase-C1 (Task C1.3) — any server id,
  including the server-down fallback sentinel `0`, is a Workspace. A `defguard` (not a plain function)
  so cockpit/keymap clause heads can gate directly on it (`when Space.workspace?(key)`) — callers must
  `require Console.Space` (a macro, unlike an ordinary `def`).
  """
  # A defguard evaluates to `false` (never raises) for any non-integer key (nil, a stray atom) — it
  # just reads as "not a Workspace".
  defguard workspace?(key) when is_integer(key)

  @doc """
  The single Workspace space in Slice 1 — the C1 bridge for call sites that used to hardcode
  `fetch(:tlon)`/`:tlon`, before multiplicity. Returns the first workspace-keyed space, or `nil`
  when server yields no workspace (even the fallback keys a workspace, so `nil` is server-genuinely-empty).
  C2 replaces these call sites with the ACTIVE workspace once there can be more than one.
  """
  @spec first_workspace() :: t() | nil
  def first_workspace, do: Enum.find(all(), &workspace?(&1.key))

  @doc "The space after `key` in picker order, wrapping around; nil when there are no spaces."
  @spec next(non_neg_integer(), [t()]) :: t() | nil
  def next(key, spaces \\ all()), do: step(key, 1, spaces)

  @doc "The space before `key` in picker order, wrapping around; nil when there are no spaces."
  @spec prev(non_neg_integer(), [t()]) :: t() | nil
  def prev(key, spaces \\ all()), do: step(key, -1, spaces)

  @doc """
  Look a space up by key, reading the live workspace cache. Returns `nil` on a miss — no silent
  default (Phase C1: `Space.fetch(:tlon)` used to paper over a stale/unknown key).
  """
  @spec fetch(atom() | non_neg_integer()) :: t() | nil
  def fetch(key), do: fetch(key, all())

  @doc "Pure `fetch/1` over an explicit spaces list — mirrors `all/0`+`all/1` (tests inject spaces)."
  @spec fetch(atom() | non_neg_integer(), [t()]) :: t() | nil
  def fetch(key, spaces), do: Enum.find(spaces, &(&1.key == key))

  @doc """
  A Workspace's roster (the cast `Console.Mention.route/3` resolves against and the spawn pass
  staffs from) — `[]` when the workspace is missing (server down / no roster: nobody resolves,
  nobody wakes). `spaces` defaults to the live cache; tests inject a list.
  """
  @spec roster(non_neg_integer() | nil, [t()]) :: [map()]
  def roster(workspace_id, spaces \\ all()) do
    case fetch(workspace_id, spaces) do
      %__MODULE__{roster: roster} -> roster
      _ -> []
    end
  end

  @doc """
  The workspace id a call site with only cockpit `state` in scope should target (a Bus handler, a
  click on a Workspace-only panel): `active_key` when it names a Workspace, else the first
  workspace — nil when none exists at all (`Console.Tmux.run/3` no-ops on nil).
  """
  @spec active_workspace_id(%{active_key: term()}) :: non_neg_integer() | nil
  def active_workspace_id(%{active_key: key}) when workspace?(key), do: key

  def active_workspace_id(_state) do
    case first_workspace() do
      nil -> nil
      space -> space.id
    end
  end

  defp step(_key, _delta, []), do: nil

  defp step(key, delta, spaces) do
    i = Enum.find_index(spaces, &(&1.key == key)) || 0
    Enum.at(spaces, rem(i + delta + length(spaces), length(spaces)))
  end
end
