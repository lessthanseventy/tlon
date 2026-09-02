defmodule Console.Space do
  @moduledoc """
  A **space** is a named lens over server — *what's in the middle* and the panels around it — the
  unit the top-left switcher picks (design Addendum §B). **Orbis** (the god-view survey — tertius'
  per-workspace rollup, the default) leads, then one **Workspace** space per server workspace (`Console.Workspaces`,
  Slice 1) — the machine/stack as a live embedded terminal. Workspace spaces are keyed by the server
  workspace id (Phase C1, not a name slug), so `[:orbis, 1]` with the single seeded workspace;
  server-down degrades to Orbis alone — server self-seeds a default workspace at boot
  (Server.Bootstrap), so no fallback Workspace is fabricated here (reshape slice A).
  Sessions is gone (its per-thread native-PTY center folded into the tmux center).
  The
  `Console.Panel.Sidebar` workspace nav switches the active one; the center renders that space's `surface`.

  A surface is a LIST of sections stacked down the center — usually one (Orbis), but a Workspace frames
  its Terminal with the NewThread and Tertius bands below. A section is either a bare
  panel module (its data shaped by `Console.View.data_for/2`, like the sidebars) or a
  `{panel_module, read_key}` pair whose data is the named Cockpit read verbatim — how two
  Terminal panes on one surface get distinct data. A space stays plain data either way.
  """

  alias Console.Panel.Activity
  alias Console.Panel.Crew
  alias Console.Panel.Memory
  alias Console.Panel.NewThread
  alias Console.Panel.Overview
  alias Console.Panel.Roster
  alias Console.Panel.Stack
  alias Console.Panel.Terminal
  alias Console.Panel.Tertius
  alias Console.Panel.Triage

  @enforce_keys [:key, :label, :surface]
  defstruct [:key, :label, :surface, :id, left: [], right: [], coworker: nil, roster: []]

  @type surface :: [module() | {module(), atom()}]
  @type t :: %__MODULE__{
          key: :orbis | non_neg_integer(),
          label: String.t(),
          surface: surface(),
          # The server workspace id (Phase C1), nil for Orbis. Mirrors `key` for a Workspace space.
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
  The spaces the switcher offers, in picker order — **Orbis first (the default)**, then one Workspace
  space per server workspace (`Console.Workspaces.all/0`, Slice 1 Task B2). `surface` is the center;
  `left`/`right` the situational sidebars. Reads the cached workspace list; `all/1` is the pure
  derivation over an explicit list (tests inject workspaces without the live cache).
  """
  @spec all() :: [t()]
  def all, do: all(fetch_workspaces())

  @doc "The picker derived from an explicit workspace list — `[Orbis | workspace_spaces(workspaces)]`."
  @spec all([map()]) :: [t()]
  def all(workspaces), do: [orbis_space() | workspace_spaces(workspaces)]

  defp orbis_space do
    %__MODULE__{
      key: :orbis,
      label: "Home",
      # The Overview IS the center now, so thread navigation lives in the feed (the focused
      # thread's block is highlighted) and the left carries presence (IN FLIGHT) instead of a
      # list the middle already shows. TRIAGE below IN FLIGHT shows cross-thread trouble.
      surface: [Overview],
      left: [Roster, Triage],
      # Slice 3.4: the right rail is retired — the god-view is spine + rail + center. The focused
      # thread's scope now reads in the center feed (its highlighted block), not a pinned Brief.
      right: []
    }
  end

  # One Workspace space per server workspace. An empty list means server is genuinely down — the app
  # self-seeds a default workspace at boot (Server.Bootstrap), so no fake Workspace is fabricated
  # here (reshape slice A); the picker degrades to Orbis alone.
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
      # Slice 3.4: the funes panels move OFF the (now-retired) right rail into the left rail, stacked
      # top-down — NOW (attention/activity) · CREW · MEMORY · STACK — no more `[`/`]` carousel. The
      # Sidebar renders as the thin far-left SPINE (workspace switcher + global tools), split out of
      # this list in `View.compose`. The center thread-stack IS the thread list; HEALTH stays in the
      # footer + /status.
      left: [Activity, Crew, Memory, Stack],
      right: [],
      coworker: lead_coworker(workspace.roster),
      roster: workspace.roster
    }
  end

  # Read the cached workspaces, degrading to [] (→ Orbis-only picker) if the cache is down mid-render.
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
  The mode predicate: is `key` a Workspace space (as opposed to `:orbis`)? Replaces the ~40
  `active_key == :tlon` guards the cockpit carried pre-Phase-C1 (Task C1.3) — any server id,
  including the server-down fallback sentinel `0`, is a Workspace. A `defguard` (not a plain function)
  so cockpit/keymap clause heads can gate directly on it (`when Space.workspace?(key)`) — callers must
  `require Console.Space` (a macro, unlike an ordinary `def`).
  """
  # A defguard evaluates to `false` (never raises) for any non-integer, non-`:orbis` key — a stray
  # `:tlon` no longer fails loudly, it just reads as "not a Workspace".
  defguard workspace?(key) when is_integer(key)

  @doc """
  The single Workspace space in Slice 1 — the C1 bridge for call sites that used to hardcode
  `fetch(:tlon)`/`:tlon`, before multiplicity. Returns the first workspace-keyed space, or `nil`
  when server yields no workspace (even the fallback keys a workspace, so `nil` is server-genuinely-empty).
  C2 replaces these call sites with the ACTIVE workspace once there can be more than one.
  """
  @spec first_workspace() :: t() | nil
  def first_workspace, do: Enum.find(all(), &workspace?(&1.key))

  @doc "The space after `key` in picker order, wrapping around."
  @spec next(:orbis | non_neg_integer()) :: t()
  def next(key), do: step(key, 1)

  @doc "The space before `key` in picker order, wrapping around."
  @spec prev(:orbis | non_neg_integer()) :: t()
  def prev(key), do: step(key, -1)

  @doc """
  Look a space up by key, reading the live workspace cache. Returns `nil` on a miss — **no** silent
  Orbis default (Phase C1: `Space.fetch(:tlon)` used to paper over a stale/unknown key).
  """
  @spec fetch(atom() | non_neg_integer()) :: t() | nil
  def fetch(key), do: fetch(key, all())

  @doc "Pure `fetch/1` over an explicit spaces list — mirrors `all/0`+`all/1` (tests inject spaces)."
  @spec fetch(atom() | non_neg_integer(), [t()]) :: t() | nil
  def fetch(key, spaces), do: Enum.find(spaces, &(&1.key == key))

  defp step(key, delta) do
    spaces = all()
    i = Enum.find_index(spaces, &(&1.key == key)) || 0
    Enum.at(spaces, rem(i + delta + length(spaces), length(spaces)))
  end
end
