defmodule Server.Recall.Probe do
  @moduledoc """
  Read-only, argv-only (no shell) checks that a `Server.Recall.CodeRefs` ref still exists on
  `origin/main` of a repo. The server never runs a fact's own `check_cmd`; these fixed probes are
  all a recheck may do.
  """

  @spec found?(Path.t(), {atom(), String.t()}) :: boolean()
  def found?(repo, {:path, path}), do: git(repo, ["cat-file", "-e", "origin/main:" <> path])
  def found?(repo, {:module, name}), do: grep(repo, "defmodule " <> esc(name) <> "( |,|$)")
  def found?(repo, {:function, name}), do: grep(repo, "defp? " <> esc(name) <> "( |\\(|,|$)")
  def found?(repo, {:task, name}), do: grep(repo, esc(name), ["--", "mise.toml", "tasks"])

  # -E with an escaped name: a bare substring would let `Server.A` pass on `Server.AB`
  defp grep(repo, pattern, paths \\ []), do: git(repo, ["grep", "-q", "-E", "-e", pattern, "origin/main"] ++ paths)

  defp esc(name), do: String.replace(name, ~r/[.?+*\[\]()|^$\\]/, "\\\\\\0")

  defp git(repo, args) do
    {_, status} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    status == 0
  end
end
