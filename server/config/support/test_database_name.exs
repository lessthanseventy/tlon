defmodule Server.TestDatabaseName do
  @moduledoc false

  # A worktree checkout at .worktrees/<name> names tlon_test_<name> (non-word chars
  # folded to _); the main checkout names tlon_test. env, when set, always wins.
  def compute(dir, env) do
    if env do
      env
    else
      case Regex.run(~r{/\.worktrees/([^/]+)/}, dir) do
        [_, name] ->
          "tlon_test_" <> String.slice(String.replace(name, ~r/[^A-Za-z0-9_]/, "_"), 0, 50)

        nil ->
          "tlon_test"
      end
    end
  end
end
