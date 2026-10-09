defmodule Server.TestDatabaseName do
  @moduledoc false

  # The checkout holding dir is found by walking up to the nearest .git. A git worktree (its .git
  # is a file) names tlon_test_<basename>_<hash of its root path>, wherever it lives (.worktrees/,
  # .claude/worktrees/, /tmp); the main checkout (.git a directory) names tlon_test. env, when
  # set, always wins. The name is cut to fit Postgres's 63-byte identifier limit.
  def compute(dir, env) do
    cond do
      env -> env
      root = worktree_root(Path.expand(dir)) -> worktree_name(root)
      true -> "tlon_test"
    end
  end

  defp worktree_root(dir) do
    git = Path.join(dir, ".git")

    cond do
      File.regular?(git) -> dir
      File.dir?(git) -> nil
      Path.dirname(dir) == dir -> nil
      true -> worktree_root(Path.dirname(dir))
    end
  end

  defp worktree_name(root) do
    base = root |> Path.basename() |> String.replace(~r/[^A-Za-z0-9_]/, "_") |> String.slice(0, 40)
    hash = :sha256 |> :crypto.hash(root) |> Base.encode16(case: :lower) |> binary_part(0, 8)
    "tlon_test_#{base}_#{hash}"
  end
end
