defmodule Server.SandboxBudget do
  @moduledoc """
  The bwrap argument budget a seat's sandbox spends. Claude Code mounts ~`args_per_repo` args per
  `.git` found under a write root (a read dir is one), and bwrap takes `bwrap_args` (#299, #455).
  `max_args` leaves headroom; `fixed_repos` are the checkouts every seat has (ficciones, tlon and its
  worktrees); `write_root_reserve` is what a seat's own scratch dir may hold. Read dirs share what is left.
  """

  @bwrap_args 9000
  @args_per_repo 45
  @fixed_repos 65
  @max_args 7500
  @write_root_reserve 40

  def bwrap_args, do: @bwrap_args
  def args_per_repo, do: @args_per_repo
  def fixed_repos, do: @fixed_repos
  def max_args, do: @max_args
  def write_root_reserve, do: @write_root_reserve

  @doc "Repos all of a project's read dirs may hold together: 166 - 65 - 40 = 61."
  def read_dir_repos, do: div(@max_args, @args_per_repo) - @fixed_repos - @write_root_reserve
end
