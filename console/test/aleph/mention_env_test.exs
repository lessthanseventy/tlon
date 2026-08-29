defmodule Console.MentionEnvTest do
  @moduledoc """
  The experiment knob on the @-mention router — the anonymised sender label ($TLON_MENTION_LABEL).
  async: false: this mutates process-global env, so it must not run concurrently with the pure
  MentionTest route cases (which assert real labels).
  """
  use ExUnit.Case, async: false

  alias Console.Mention

  # The seed roster (Console.Space's fallback Tlön workspace) — mirrors mention_test.exs's fixture.
  @roster [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "builder", "name" => "hronir"}]

  setup do
    on_exit(fn -> System.delete_env("TLON_MENTION_LABEL") end)
    :ok
  end

  describe "TLON_MENTION_LABEL=anon — strip the sender persona" do
    test "labels the injected turn 'someone' instead of the real handle" do
      System.put_env("TLON_MENTION_LABEL", "anon")

      assert Mention.route(%{author: "tertius-machine", body: "@hronir-machine who are you", thread_id: 1}, [], @roster) ==
               [{"hronir", "[tlon thread #1] someone: @hronir-machine who are you"}]
    end

    test "any other value keeps the real label" do
      System.put_env("TLON_MENTION_LABEL", "real")

      assert Mention.route(%{author: "tertius-machine", body: "@hronir-machine hi", thread_id: 1}, [], @roster) ==
               [{"hronir", "[tlon thread #1] tertius-machine: @hronir-machine hi"}]
    end
  end
end
