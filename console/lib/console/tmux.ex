defmodule Console.Tmux do
  @moduledoc """
  The one owner of the cockpit's tmux naming contract and the command seam behind it.

  Every workspace runs its coworkers on a PRIVATE tmux server — socket `console-workspace-<id>`,
  session `w<id>` — both id-derived, so a workspace rename can't orphan a running session and two
  workspaces never collide (and never touch the operator's default server). Inside a session: the
  roster lead is window 0 (named after the lead), tail coworkers are named windows, a staffed
  thread's leaf carries the `@funes_thread <id>` window option (the routing key — its name is
  cosmetic; a legacy `t<id>` name still resolves), crew roles are `r<id>`.

  Every call routes through `run/3`: the runner defaults to `System.cmd/3`, overridable through
  `:console, :tlon_cmd` (the test seam) or a per-call `runner:` (`Server.Crew.Tmux` passes its own
  `:crew_cmd` runner so its seam stays distinct).
  """

  @type tab :: %{
          name: String.t(),
          active?: boolean(),
          index: String.t(),
          thread_id: integer() | nil,
          opening: String.t() | nil,
          activity: integer() | nil,
          pane_pid: integer() | nil
        }

  @type runner :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})

  @doc "The workspace's tmux session name."
  @spec session(term()) :: String.t()
  def session(id), do: "w#{id}"

  @doc "The workspace's private tmux server socket (`-L`)."
  @spec socket(term()) :: String.t()
  def socket(id), do: "console-workspace-#{id}"

  @doc "A `session:window` target; `window` is an index, a name, or `=name` for an exact-name match."
  @spec target(term(), term()) :: String.t()
  def target(id, window), do: "#{session(id)}:#{window}"

  @doc "The full argv for a call against workspace `id`'s server — `-L <socket>` ahead of `args`."
  @spec argv(term(), [String.t()]) :: [String.t()]
  def argv(id, args), do: ["-L", socket(id)] ++ args

  @doc """
  Run `tmux` against workspace `id`'s server. A nil id (no workspace at all — server down) is a
  no-op with a nonzero "exit", never a call without `-L` that would land on the operator's own
  tmux server. `opts[:runner]` overrides the `:tlon_cmd` seam.
  """
  @spec run(term() | nil, [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def run(id, args, opts \\ [])
  def run(nil, _args, _opts), do: {"no active workspace", 1}

  def run(id, args, opts) do
    runner = Keyword.get_lazy(opts, :runner, fn -> Application.get_env(:console, :tlon_cmd, &System.cmd/3) end)
    runner.("tmux", argv(id, args), stderr_to_stdout: true)
  end

  @list_format "\#{window_active}\t\#{window_index}\t\#{window_name}\t\#{@funes_thread}\t\#{@funes_opening}\t\#{window_activity}\t\#{pane_pid}"

  @doc "The session's windows as tabs, straight from tmux (a session not up yet is `[]`)."
  @spec list_windows(term() | nil, keyword()) :: [tab()]
  def list_windows(id, opts \\ []) do
    case run(id, ["list-windows", "-t", session(id), "-F", @list_format], opts) do
      {out, 0} -> parse_windows(out)
      _ -> []
    end
  end

  @doc """
  Parse `list-windows` output: one `<active>\\t<index>\\t<name>\\t<@funes_thread>\\t<@funes_opening>\\t<activity>`
  line per window. `index` is tmux's window index (the `select-window` target); `@funes_thread`
  is the leaf routing key (empty for non-leaf windows → nil); `@funes_opening` is the leaf's
  opening-turn phase (`"typed"`/`"done"`, kept in tmux so a cockpit restart can't replay it);
  `window_activity` is the last-content-change unix time. Shorter lines still parse, missing
  fields nil; a malformed line is dropped.
  """
  @spec parse_windows(String.t()) :: [tab()]
  def parse_windows(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 7) do
        [active, index, name | rest] when rest != [] or name != "" ->
          [thread, opening, activity, pane_pid] = Enum.map(0..3, &Enum.at(rest, &1, ""))

          [
            %{
              name: name,
              active?: active == "1",
              index: index,
              thread_id: int_or_nil(thread),
              opening: if(opening in ["typed", "done"], do: opening),
              activity: int_or_nil(activity),
              pane_pid: int_or_nil(pane_pid)
            }
          ]

        _ ->
          []
      end
    end)
  end

  defp int_or_nil(s) do
    case Integer.parse(s) do
      {id, ""} -> id
      _ -> nil
    end
  end

  @doc "The window index of the tab named `name`, or nil."
  @spec window_index([tab()], String.t()) :: String.t() | nil
  def window_index(tabs, name), do: Enum.find_value(tabs, fn %{name: n, index: index} -> if n == name, do: index end)

  @doc """
  The tab running thread `id`'s leaf session: the `@funes_thread`-tagged window, else a legacy
  `t<id>`-named one — nil when the leaf has no window. Thread → window resolves HERE, never by
  parsing a (human-named) window name.
  """
  @spec leaf_tab([tab()], integer()) :: tab() | nil
  def leaf_tab(tabs, id), do: Enum.find(tabs, &(&1.thread_id == id)) || Enum.find(tabs, &(&1.name == "t#{id}"))

  @doc """
  The window index the SESSION pane attaches to for thread `id`: its own leaf window, or — when `id`
  is the STANDING thread, whose coworker runs in the CENTRE window (named for the roster lead) and
  so never gets a leaf — that window. nil when neither is up.
  """
  @spec pane_index([tab()], integer(), integer() | nil, String.t() | nil) :: String.t() | nil
  def pane_index(tabs, id, standing_id, lead_name)
  def pane_index(tabs, id, id, lead_name) when is_binary(lead_name), do: window_index(tabs, lead_name)
  def pane_index(_tabs, id, id, nil), do: nil
  def pane_index(tabs, id, _standing_id, _lead_name), do: leaf_tab(tabs, id)[:index]

  @doc "Is this tab a LEAF session (a `@funes_thread` tag or a legacy `t<id>` name), vs the center/tail windows?"
  @spec leaf_window?(tab()) :: boolean()
  def leaf_window?(%{thread_id: tid}) when is_integer(tid), do: true
  def leaf_window?(%{name: name}), do: Regex.match?(~r/\At\d+\z/, name)

  @doc "Kill `window` (index or name) in the workspace session. Best-effort."
  @spec kill_window(term() | nil, term(), keyword()) :: :ok
  def kill_window(id, window, opts \\ []) do
    _ = run(id, ["kill-window", "-t", target(id, window)], opts)
    :ok
  end

  @doc "Point the session's client at `window` (index or name). Best-effort."
  @spec select_window(term() | nil, term(), keyword()) :: :ok
  def select_window(id, window, opts \\ []) do
    _ = run(id, ["select-window", "-t", target(id, window)], opts)
    :ok
  end

  @doc "Set a window option on `window` (index, name, or `=name` for exact match). Best-effort."
  @spec set_window_option(term() | nil, term(), String.t(), String.t(), keyword()) :: :ok
  def set_window_option(id, window, name, value, opts \\ []) do
    _ = run(id, ["set-option", "-w", "-t", target(id, window), name, value], opts)
    :ok
  end

  @doc """
  Type literal `text` into `window` WITHOUT submitting — the first half of the two-phase inject.
  A just-booted harness TUI takes text but swallows an Enter arriving in the same burst, so
  `submit/3` follows on a later pass once the TUI has settled.
  """
  @spec send_text(term() | nil, term(), String.t(), keyword()) :: :ok
  def send_text(id, window, text, opts \\ []) do
    _ = run(id, ["send-keys", "-l", "-t", target(id, window), text], opts)
    :ok
  end

  @doc "Send Enter to `window` — submits whatever its input holds (the second half of the inject)."
  @spec submit(term() | nil, term(), keyword()) :: :ok
  def submit(id, window, opts \\ []) do
    _ = run(id, ["send-keys", "-t", target(id, window), "Enter"], opts)
    :ok
  end
end
