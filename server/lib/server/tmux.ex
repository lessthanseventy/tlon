defmodule Server.Tmux do
  @moduledoc """
  The tmux naming contract the whole machine shares, and the server's command seam behind it
  (one-brain piece B, slice 1). Every workspace runs its coworkers on a PRIVATE tmux server —
  socket `console-workspace-<id>`, session `w<id>`, both id-derived so a rename never orphans a
  running session; a staffed thread's leaf window carries the `@funes_thread <id>` option (the
  routing key — its name is cosmetic; a legacy `t<id>` name still resolves). `Console.Tmux` is
  the same contract on the console side; the names are defined here so a client (the console,
  asterion) and the server can never disagree about where a coworker runs.

  Every call routes through `run/3`: `System.cmd/3` by default, `config :server, :tmux_cmd` is
  the test seam. Like `Server.Workline.Artifacts.Git`, a tmux fault is a value, never a raise.
  """

  @type tab :: %{name: String.t(), index: String.t(), thread_id: integer() | nil, pane_pid: integer() | nil}

  def session(id), do: "w#{id}"
  def socket(id), do: "console-workspace-#{id}"
  def target(id, window), do: "#{session(id)}:#{window}"
  def argv(id, args), do: ["-L", socket(id)] ++ args

  @doc "Run tmux against workspace `id`'s server; a nil id (no workspace) is a nonzero no-op, never a call on the operator's own tmux."
  def run(id, args, opts \\ [])
  def run(nil, _args, _opts), do: {"no workspace", 1}

  def run(id, args, opts) do
    runner = Keyword.get_lazy(opts, :runner, fn -> Application.get_env(:server, :tmux_cmd, &System.cmd/3) end)
    runner.("tmux", argv(id, args), stderr_to_stdout: true)
  end

  @list_format "\#{window_index}\t\#{window_name}\t\#{@funes_thread}\t\#{pane_pid}"

  @doc "The session's windows (a session not up is `[]`)."
  def list_windows(id, opts \\ []) do
    case run(id, ["list-windows", "-t", session(id), "-F", @list_format], opts) do
      {out, 0} -> parse_windows(out)
      _ -> []
    end
  end

  def parse_windows(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 4) do
        [index, name | rest] when name != "" ->
          [thread, pid] = Enum.map(0..1, &Enum.at(rest, &1, ""))
          [%{index: index, name: name, thread_id: int_or_nil(thread), pane_pid: int_or_nil(pid)}]

        _ ->
          []
      end
    end)
  end

  defp int_or_nil(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> nil
    end
  end

  @doc "The tab running thread `id`'s leaf: the `@funes_thread`-tagged window, else a legacy `t<id>`."
  def leaf_tab(tabs, id), do: Enum.find(tabs, &(&1.thread_id == id)) || Enum.find(tabs, &(&1.name == "t#{id}"))

  @doc "The tab named `name`, or nil."
  def named(tabs, name), do: Enum.find(tabs, &(&1.name == name))

  def session_up?(id, opts \\ []), do: match?({_, 0}, run(id, ["has-session", "-t", session(id)], opts))

  @doc "Type literal `text` without submitting, then `submit/3` sends Enter — two bursts, or a booting TUI swallows the Enter."
  def send_text(id, window, text, opts \\ []), do: run(id, ["send-keys", "-l", "-t", target(id, window), text], opts)
  def submit(id, window, opts \\ []), do: run(id, ["send-keys", "-t", target(id, window), "Enter"], opts)

  def set_window_option(id, window, name, value, opts \\ []),
    do: run(id, ["set-option", "-w", "-t", target(id, window), name, value], opts)

  def kill_window(id, window, opts \\ []), do: run(id, ["kill-window", "-t", target(id, window)], opts)

  @doc """
  A harness window's boot script (lifted verbatim from `Console.Staffing.boot_script/2`, the one
  builder every harness window rides): close every inherited fd above stderr (a beam socket rode
  into a coworker's tmux on 2026-09-08 and hung every later `mix`), set TERM so the harness
  produces colour, source the server `exports`, cd into the thread's worktree when it has one,
  `exec` the bare launcher. POSIX sh — callers run it with `/bin/sh -c`, never tmux's
  default-shell (zsh kills the fd loop with status 127 and no output).
  """
  def boot_script(exports, command) do
    ~s|for fd in $(ls /proc/$$/fd); do [ "$fd" -gt 2 ] && eval "exec $fd>&-"; done 2>/dev/null| <>
      "\nexport TERM=xterm-256color\n" <>
      exports <> "\n" <> ~s([ -n "$TLON_CWD" ] && cd "$TLON_CWD") <> "\nexec " <> command
  end

  @doc "POSIX single-quote `s` so it survives a shell verbatim."
  def sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"
end
