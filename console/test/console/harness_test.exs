defmodule Console.HarnessTest do
  @moduledoc """
  Environment-resolved harness binding + the per-harness driver contract (Slice D). The ToS rule:
  an anthropic-provider model at HOME binds to claude_code (the official harness); everything else
  — work/API, or a non-anthropic model anywhere — binds to pi.
  """
  use ExUnit.Case, async: false

  alias Console.Config
  alias Console.Harness
  alias Console.Profile
  alias Console.Profiles

  @sonnet %{provider: "anthropic", model: "claude-sonnet-5", thinking: "medium"}
  @glm %{provider: "ollama-cloud", model: "glm-5.2", thinking: "medium"}

  setup do
    prior = System.get_env("TLON_ENV")

    on_exit(fn ->
      if prior, do: System.put_env("TLON_ENV", prior), else: System.delete_env("TLON_ENV")
    end)

    System.delete_env("TLON_ENV")
    :ok
  end

  describe "resolve/2 — the ToS rule" do
    test "anthropic model at home → claude_code (never a third-party harness on the personal sub)" do
      assert Harness.resolve(@sonnet, "home") == :claude_code
    end

    test "anthropic model at work (API-billed) → pi" do
      assert Harness.resolve(@sonnet, "work") == :pi
    end

    test "a non-anthropic model → pi anywhere; nil model inherits base defaults → pi" do
      assert Harness.resolve(@glm, "home") == :pi
      assert Harness.resolve(@glm, "work") == :pi
      assert Harness.resolve(nil, "home") == :pi
    end
  end

  describe "Config.environment/1" do
    test "defaults to home (test config points at a nonexistent file)" do
      assert Config.environment() == "home"
    end

    test "TLON_ENV wins" do
      System.put_env("TLON_ENV", "work")
      assert Config.environment() == "work"
    end

    test "the config file's environment key is read when no env var is set" do
      path = Path.join(System.tmp_dir!(), "aleph_env_test_#{System.unique_integer([:positive])}.json")
      File.write!(path, ~s({"environment": "work"}))
      on_exit(fn -> File.rm(path) end)

      assert Config.environment(path) == "work"
    end
  end

  describe "instantiate/1 binds the harness from model × environment" do
    test "at home, every anthropic-model archetype rides claude_code; the glm surveyor rides pi" do
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :reviewer, name: "vera"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :planner, name: "borges"}).harness == :claude_code
      assert Profiles.instantiate(%{archetype: :surveyor, name: "tertius"}).harness == :pi
    end

    test "at work the same archetypes bind to pi — the personal sub is out of the loop" do
      System.put_env("TLON_ENV", "work")
      assert Profiles.instantiate(%{archetype: :builder, name: "hronir"}).harness == :pi
      assert Profiles.instantiate(%{archetype: :reviewer, name: "vera"}).harness == :pi
    end

    test "a roster-entry model override re-resolves the binding (ollama planner at home → pi)" do
      assert Profiles.instantiate(%{archetype: :planner, name: "borges", model: @glm}).harness == :pi
    end
  end

  describe "the driver contract" do
    test "claude_code: launch.sh with the persona file env + --model for an anthropic model" do
      p = %Profile{name: "vera", archetype: :reviewer, model: @sonnet, system_prompt: "You review."}
      cmd = Harness.driver(:claude_code).launch_command(p)

      assert cmd =~ "modules/adapters/claude-code/launch.sh"
      assert cmd =~ "TLON_ROLE_PROMPT_FILE="
      assert cmd =~ "profiles/vera/system_prompt.md"
      assert cmd =~ "--model claude-sonnet-5"
      refute cmd =~ "PI_CODING_AGENT_DIR"
    end

    test "claude_code: a write-denying policy (the reviewer) exports the permissions fence" do
      reviewer = Profiles.instantiate(%{archetype: :reviewer, name: "vera"})
      builder = Profiles.instantiate(%{archetype: :builder, name: "hronir"})

      assert reviewer.harness == :claude_code
      assert Harness.driver(:claude_code).launch_command(reviewer) =~ "TLON_PERMISSIONS_DENY=Write,Edit,NotebookEdit"
      refute Harness.driver(:claude_code).launch_command(builder) =~ "TLON_PERMISSIONS_DENY"
    end

    test "claude_code: no persona → the bare launcher, no env prefix" do
      p = %Profile{name: "plain", model: @sonnet}
      cmd = Harness.driver(:claude_code).launch_command(p)
      refute cmd =~ "TLON_ROLE_PROMPT_FILE"
      assert String.contains?(cmd, "launch.sh --model claude-sonnet-5")
    end

    test "pi: PI_CODING_AGENT_DIR + persona + provider-qualified --model" do
      p = %Profile{name: "borges", model: @glm, system_prompt: "You plan."}
      cmd = Harness.driver(:pi).launch_command(p)

      assert cmd =~ "PI_CODING_AGENT_DIR="
      assert cmd =~ "--append-system-prompt"
      assert cmd =~ "--model ollama-cloud/glm-5.2 --thinking medium"
    end
  end
end
