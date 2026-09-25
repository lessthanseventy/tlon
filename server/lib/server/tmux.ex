defmodule Server.Tmux do
  @moduledoc """
  The tmux naming contract the whole machine shares, and the server's command seam behind it
  (one-brain piece B). Every workspace runs its coworkers on a PRIVATE tmux server — socket
  `console-workspace-<id>`, session `w<id>`, both id-derived so a rename never orphans a running
  session; the roster lead is the CENTRE window (named after the lead), tail coworkers are named
  windows, a staffed thread's leaf window carries the `@funes_thread <id>` option (the routing
  key — its name is cosmetic; a legacy `t<id>` name still resolves) and its opening-turn phase as
  `@funes_opening`, crew roles are `r<id>`. `Console.Tmux` is the same contract on the console
  side; the names are defined here so a client (the console, asterion) and the server can never
  disagree about where a coworker runs.

  Every call routes through `run/3`: `System.cmd/3` by default, `config :server, :tmux_cmd` is
  the test seam. Like `Server.Workline.Artifacts.Git`, a tmux fault is a value, never a raise.
  """

  @type tab :: %{
          name: String.t(),
          index: String.t(),
          thread_id: integer() | nil,
          opening: String.t() | nil,
          pane_pid: integer() | nil
        }

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

  @list_format "\#{window_index}\t\#{window_name}\t\#{@funes_thread}\t\#{@funes_opening}\t\#{pane_pid}"

  @doc "The session's windows (a session not up is `[]`)."
  def list_windows(id, opts \\ []) do
    case run(id, ["list-windows", "-t", session(id), "-F", @list_format], opts) do
      {out, 0} -> parse_windows(out)
      _ -> []
    end
  end

  @doc """
  Parse `list-windows` output: `<index>\\t<name>\\t<@funes_thread>\\t<@funes_opening>\\t<pane_pid>` per
  window. Shorter lines still parse, missing fields nil; a malformed line is dropped.
  """
  def parse_windows(out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(line, "\t", parts: 5) do
        [index, name | rest] when name != "" ->
          [thread, opening, pid] = Enum.map(0..2, &Enum.at(rest, &1, ""))

          [
            %{
              index: index,
              name: name,
              thread_id: int_or_nil(thread),
              opening: if(opening in ["typed", "done"], do: opening),
              pane_pid: int_or_nil(pid)
            }
          ]

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

  @doc "Is this tab a LEAF session (a `@funes_thread` tag or a legacy `t<id>` name), vs the centre/tail/crew windows?"
  def leaf_window?(%{thread_id: tid}) when is_integer(tid), do: true
  def leaf_window?(%{name: name}), do: Regex.match?(~r/\At\d+\z/, name)

  def session_up?(id, opts \\ []), do: match?({_, 0}, run(id, ["has-session", "-t", session(id)], opts))

  @doc "Type literal `text` without submitting, then `submit/3` sends Enter — two bursts, or a booting TUI swallows the Enter."
  def send_text(id, window, text, opts \\ []), do: run(id, ["send-keys", "-l", "-t", target(id, window), text], opts)
  def submit(id, window, opts \\ []), do: run(id, ["send-keys", "-t", target(id, window), "Enter"], opts)

  def set_window_option(id, window, name, value, opts \\ []),
    do: run(id, ["set-option", "-w", "-t", target(id, window), name, value], opts)

  def kill_window(id, window, opts \\ []), do: run(id, ["kill-window", "-t", target(id, window)], opts)

  @doc """
  A harness window's boot script (lifted verbatim from the console's staffing, the one builder
  every harness window rides): close every inherited fd above stderr (a beam socket rode into a
  coworker's tmux on 2026-09-08 and hung every later `mix`), set TERM so the harness produces
  colour, source the server `exports`, cd into the thread's worktree when it has one, `exec` the
  bare launcher. POSIX sh — callers run it with `/bin/sh -c`, never tmux's default-shell (zsh
  kills the fd loop with status 127 and no output).
  """
  def boot_script(exports, command) do
    close_inherited_fds() <>
      "\nexport TERM=xterm-256color\n" <> exports <> "\n" <> cd_worktree() <> "\nexec " <> command
  end

  @doc "The boot script's first line: close every fd above stderr."
  def close_inherited_fds,
    do: ~s|for fd in $(ls /proc/$$/fd); do [ "$fd" -gt 2 ] && eval "exec $fd>&-"; done 2>/dev/null|

  @doc "The line every harness boot takes after sourcing the exports: into the thread's worktree, guarded."
  def cd_worktree, do: ~s([ -n "$TLON_CWD" ] && cd "$TLON_CWD")

  @doc "POSIX single-quote `s` so it survives a shell verbatim."
  def sh_single_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"

  @doc """
  `-e VAR=value` pairs for the TLON_* identity in an `exports` block, so `new-session`/`new-window`
  carry it in the tmux env — durable across a `respawn-pane` or a `--continue` reload, where the
  one-shot boot shell's exports are gone and the harness would come up with `${TLON_MCP_URL}` empty.
  """
  def identity_flags(exports) do
    ~r/^export (TLON_(?:MCP_URL|THREAD|AUTHOR|CWD))="([^"]*)"/m
    |> Regex.scan(exports)
    |> Enum.flat_map(fn [_, k, v] -> ["-e", k <> "=" <> v] end)
  end
end
