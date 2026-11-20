defmodule Server.Home.SourcesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Server.Home.Sources
  alias Server.Jot
  alias Server.Proposal

  @now ~U[2026-11-19 12:00:00Z]

  setup do
    Server.TestDB.clean!()
  end

  defmodule Failing do
    @moduledoc false
    def name, do: "failing"
    def auto, do: []
    def fetch, do: {:error, Process.get(:reason, "down")}
  end

  test "a failing source is logged once per distinct reason" do
    modules = %{"failing" => Failing}

    log =
      capture_log(fn ->
        failed = Sources.poll("telegram", ["failing"], modules, @now, %{})
        assert failed == %{"failing" => "down"}
        failed = Sources.poll("telegram", ["failing"], modules, @now, failed)
        Process.put(:reason, "still down")
        Sources.poll("telegram", ["failing"], modules, @now, failed)
      end)

    assert length(String.split(log, "home source failing")) == 3
    assert log =~ "still down"
  end

  test "a source that raises, or is not one, is a failure and not a crash" do
    defmodule Broken do
      @moduledoc false
      def name, do: "broken"
      def auto, do: []
      def fetch, do: raise("boom")
    end

    capture_log(fn ->
      assert %{"broken" => "boom", "nope" => :unknown} =
               Sources.poll("telegram", ["broken", "nope"], %{"broken" => Broken}, @now, %{})
    end)
  end

  test "a name with no module is logged once as no such source" do
    log =
      capture_log(fn ->
        failed = Sources.poll("telegram", ["github"], %{}, @now, %{})
        assert failed == %{"github" => :unknown}
        Sources.poll("telegram", ["github"], %{}, @now, failed)
      end)

    assert length(String.split(log, "home source github: no such source")) == 2
  end

  test "a trusted proposal that cannot be filed is logged once per key, and filed when it can be" do
    defmodule Stub do
      @behaviour Server.Home.Source

      def name, do: "stub"
      def auto, do: ["waiting"]

      def fetch, do: {:ok, [%{key: "w", text: "Waiting on review: PR 1", kind: "waiting", who: "x"}], []}
    end

    Proposal.offer("telegram", "stub", [%{key: "w", text: "Waiting on review: PR 1", kind: "waiting"}], @now, [])
    [row] = Proposal.open()
    {:ok, _} = Jot.take("telegram", Proposal.external_id(row), "in the way")
    modules = %{"stub" => Stub}

    log =
      capture_log(fn ->
        failed = Sources.poll("telegram", ["stub"], modules, @now, %{})
        assert failed == %{{"stub", "w"} => :seen}
        failed = Sources.poll("telegram", ["stub"], modules, @now, failed)
        assert failed == %{{"stub", "w"} => :seen}
      end)

    assert length(String.split(log, "home source stub: w could not be filed")) == 2
    assert [%{state: :open}] = Proposal.open()
  end

  test "home_sources names the sources: a comma list, empty for none" do
    assert Sources.names("mail") == ["mail"]
    assert Sources.names(" mail, jira ,") == ["mail", "jira"]
    assert Sources.names("") == []
  end
end
