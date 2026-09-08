defmodule Console.SessionPane do
  @moduledoc """
  Launch spec for the toggleable right SESSION PANE (2026-08-31). A thread's lead runs as a live
  agent in a tmux window of the workspace session; toggling the pane on a selected thread embeds
  that window in a `Console.Terminal` PTY beside the thread stack, driven with the same
  `Ctrl+Space` TERM↔NAV leader as any embedded app. This module ONLY builds the attach command;
  the cockpit owns the terminal lifecycle (spawn on show, retarget as the cursor moves).

  LIVE-tunable (Andrew's kitty pass): the exact attach shape — a plain `attach` shares the center
  client's current window, so the pane opens a **grouped** session (`new-session -t`) that shares
  the windows but keeps its OWN current window, then selects the lead's. Tune the grouping/resize
  semantics against a running cockpit.
  """

  @doc ~S"""
  The PTY command to view the lead window `index` of workspace `workspace_id`'s session for thread
  `thread_id` — a grouped tmux client pinned to that window. `{"/bin/bash", ["-lc", "exec tmux …"]}`:
  a login shell so PATH/env resolve like the harness terminals; `exec` so tmux becomes the PTY's own
  process. All interpolations are single-quoted so a name can't split the command.

  The view session is named PER THREAD: `-A` attaches to an existing one, so a workspace-wide name
  put every open thread's pane on the same client — whose current window the newest `select-window`
  moved, leaving the older pane showing the newer thread's coworker.
  """
  def command(workspace_id, index, thread_id) do
    socket = Console.Tmux.socket(workspace_id)
    session = Console.Tmux.session(workspace_id)
    view = "#{session}_view_#{thread_id}"
    target = "#{session}:#{index}"

    script =
      "exec tmux -L #{q(socket)} new-session -A -s #{q(view)} -t #{q(session)} " <>
        "\\; select-window -t #{q(target)}"

    {"/bin/bash", ["-lc", script]}
  end

  # POSIX single-quote: wrap in '…', and render an embedded ' as '\'' (close, escaped-quote, reopen).
  defp q(s), do: "'" <> String.replace(to_string(s), "'", "'\\''") <> "'"
end
