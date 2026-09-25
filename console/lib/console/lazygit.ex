defmodule Console.Lazygit do
  @moduledoc """
  Launch spec for the embedded lazygit. A thread's git lives on branch `work/<slug>` in a per-thread
  worktree (`Server.Worktree`); lazygit runs there in a `Console.Terminal` PTY, keyed `{:lazygit, id}`.
  One PTY, two places: the git pane under the session pane (live while the thread is open), and the
  full-frame zoom (`Alt+z`, or `Enter` on STACK) that takes the keys until `Ctrl+Space`. This module
  ONLY builds the command; the cockpit owns the terminal lifecycle.
  """

  @doc "Whether lazygit is installed (on PATH). The zoom degrades to a flash when it isn't."
  def available?, do: System.find_executable("lazygit") != nil

  @doc """
  The PTY command to run lazygit in `cwd`: a login shell so PATH/env resolve like the harness
  terminals, and `exec` so lazygit becomes the PTY's own process (quitting it ends the pane). `cwd`
  is single-quoted, so spaces and quotes can't split it or break out.

      iex> Console.Lazygit.command("/tmp/a dir/wt")
      {"/bin/bash", ["-lc", "cd '/tmp/a dir/wt' && exec lazygit"]}

      iex> Console.Lazygit.command("/tmp/it's")
      {"/bin/bash", ["-lc", "cd '/tmp/it'\\\\''s' && exec lazygit"]}
  """
  def command(cwd) do
    {"/bin/bash", ["-lc", "cd #{shell_quote(cwd)} && exec lazygit"]}
  end

  # POSIX single-quote: wrap in '…', and render an embedded ' as '\'' (close, escaped-quote, reopen).
  defp shell_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"
end
