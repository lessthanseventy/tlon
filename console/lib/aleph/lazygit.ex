defmodule Console.Lazygit do
  @moduledoc """
  Launch spec for the STACK-zoom embedded lazygit (Slice 4). A thread's git lives on branch
  `work/<slug>` in a per-thread worktree (`Server.Worktree`); zooming STACK opens `lazygit` there
  in a `Console.Terminal` PTY, driven with the same `Ctrl+Space` TERM↔NAV leader as any embedded
  app — no new input model. This module ONLY builds the command; the cockpit owns the terminal
  lifecycle (spawn on zoom, kill on collapse).
  """

  @doc "Whether lazygit is installed (on PATH). The zoom degrades to a flash when it isn't."
  def available?, do: System.find_executable("lazygit") != nil

  @doc ~S"""
  The PTY command to run lazygit in `cwd` — `{"/bin/bash", ["-lc", "cd … && exec lazygit"]}`.
  A login shell so PATH/env resolve like the harness terminals; `exec` so lazygit becomes the PTY's
  own process (quitting it ends the pane). `cwd` is single-quoted so spaces/specials can't split it.
  """
  def command(cwd) do
    {"/bin/bash", ["-lc", "cd #{shell_quote(cwd)} && exec lazygit"]}
  end

  # POSIX single-quote: wrap in '…', and render an embedded ' as '\'' (close, escaped-quote, reopen).
  defp shell_quote(s), do: "'" <> String.replace(s, "'", "'\\''") <> "'"
end
