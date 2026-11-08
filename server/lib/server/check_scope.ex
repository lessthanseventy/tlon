defmodule Server.CheckScope do
  @moduledoc """
  Which gates a branch's diff can break: the suites a verify runs, chosen from the paths the
  branch touched (`workline-verify.sh` asks over `POST /api/check/scope`). The landing's gate is
  always the full `check`; this only narrows the runs before it, so a cross-module break reaches
  the landing one round later, never past it.
  """

  @full ["check"]
  @greps ["check:names", "check:ignored"]

  @doc """
  The mise tasks for a diff: one module's own gates when every path is in that module, the full
  `check` when the paths span modules, touch a root file, `mise.toml`, a check script, an
  `AGENTS.md` or `.github/`, or when there are none. The server suite is the script tests'
  harness, so a `scripts/` or `tasks/` change runs it too.
  """
  @spec suites([String.t()]) :: [String.t()]
  def suites([]), do: @full

  def suites(paths) do
    if Enum.any?(paths, &cross?/1) do
      @full
    else
      paths
      |> Enum.map(&area/1)
      |> Enum.uniq()
      |> case do
        [area] -> tasks(area)
        _ -> @full
      end
    end
  end

  defp cross?("mise.toml"), do: true
  defp cross?(".github/" <> _), do: true
  defp cross?("scripts/check" <> _), do: true
  defp cross?(path), do: Path.basename(path) == "AGENTS.md"

  defp area("server/" <> _), do: :server
  defp area("office/" <> _), do: :office
  defp area("adapters/claude-code/" <> _), do: :claude_code
  defp area("adapters/lsp/" <> _), do: :lsp
  defp area("adapters/lspd/" <> _), do: :lspd
  defp area("scripts/" <> _), do: :scripts
  defp area("tasks/" <> _), do: :scripts
  defp area("docs/" <> _), do: :docs
  defp area("work/" <> _), do: :docs
  defp area(_), do: :other

  defp tasks(:server), do: @greps ++ ["server:check", "server:eval-det"]
  defp tasks(:office), do: @greps ++ ["office:check"]
  defp tasks(:claude_code), do: @greps ++ ["adapters:claude-code:check", "adapters:claude-code:mod"]
  defp tasks(:lsp), do: @greps ++ ["adapters:lsp:check"]
  defp tasks(:lspd), do: @greps ++ ["adapters:lspd:check"]
  defp tasks(:scripts), do: @greps ++ ["check:scripts", "server:check"]
  defp tasks(:docs), do: @greps ++ ["manual:check"]
  defp tasks(:other), do: @full
end
