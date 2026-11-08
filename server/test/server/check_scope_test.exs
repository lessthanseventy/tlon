defmodule Server.CheckScopeTest do
  use ExUnit.Case, async: true

  alias Server.CheckScope

  @greps ["check:names", "check:ignored"]

  test "one module's paths run that module's gates beside the grep gates" do
    assert CheckScope.suites(["server/lib/server/x.ex", "server/test/server/x_test.exs"]) ==
             @greps ++ ["server:check", "server:eval-det"]

    assert CheckScope.suites(["office/kit/sim.ts"]) == @greps ++ ["office:check"]

    assert CheckScope.suites(["adapters/claude-code/mod.ts"]) ==
             @greps ++ ["adapters:claude-code:check", "adapters:claude-code:mod"]

    assert CheckScope.suites(["adapters/lsp/a.ts"]) == @greps ++ ["adapters:lsp:check"]
    assert CheckScope.suites(["adapters/lspd/a.ts"]) == @greps ++ ["adapters:lspd:check"]
    assert CheckScope.suites(["docs/plans/a.md", "work/slug/spec.md"]) == @greps ++ ["manual:check"]
  end

  test "a server-only diff never skips the server suite" do
    for path <- ["server/mix.exs", "server/config/test.exs", "server/priv/repo/migrations/1_a.exs"] do
      assert "server:check" in CheckScope.suites([path])
    end
  end

  test "scripts and tasks run the script tests and the server suite that harnesses them" do
    assert CheckScope.suites(["scripts/workline-verify.sh", "tasks/server.toml"]) ==
             @greps ++ ["check:scripts", "server:check"]
  end

  test "paths across modules, a root file, or nothing at all are the full check" do
    assert CheckScope.suites(["server/lib/a.ex", "office/kit/a.ts"]) == ["check"]
    assert CheckScope.suites(["README.md"]) == ["check"]
    assert CheckScope.suites(["adapters/other/a.ts"]) == ["check"]
    assert CheckScope.suites([]) == ["check"]
  end

  test "each cross-cutting path forces the full check whatever else is in the diff" do
    for path <- [
          "mise.toml",
          "scripts/check.sh",
          "scripts/check-names.sh",
          "AGENTS.md",
          "server/AGENTS.md",
          ".github/workflows/a.yml"
        ] do
      assert CheckScope.suites(["server/lib/a.ex", path]) == ["check"], path
    end
  end
end
