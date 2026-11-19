defmodule Server.Home.SourcesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Server.Home.Source.GitHub
  alias Server.Home.Sources
  alias Server.Jot
  alias Server.Proposal

  @now ~U[2026-11-19 12:00:00Z]

  setup do
    Server.TestDB.clean!()

    on_exit(fn ->
      Application.delete_env(:server, :home_gh)
      Application.delete_env(:server, :home_source_modules)
    end)
  end

  defp pr(n, title, opts \\ []) do
    %{
      "number" => n,
      "title" => title,
      "url" => "https://github.com/#{opts[:repo] || "acme/app"}/pull/#{n}",
      "author" => %{"login" => opts[:author] || "sam"},
      "repository" => %{"nameWithOwner" => opts[:repo] || "acme/app"},
      "isDraft" => opts[:draft] || false
    }
  end

  # gh, stubbed: each search's answer by the flag that tells them apart
  defp gh(asked, changes, waiting) do
    me = self()

    Application.put_env(:server, :home_gh, fn args ->
      send(me, {:gh, args})

      answer =
        cond do
          "--review-requested=@me" in args -> asked
          "--review=changes_requested" in args -> changes
          "--review=none" in args -> waiting
        end

      case answer do
        {:error, _} = error -> error
        prs -> {:ok, JSON.encode!(prs)}
      end
    end)
  end

  test "review requests, changes requested and PRs nobody has reviewed become proposals; drafts and ignored repos are left out" do
    gh(
      [
        pr(1, "Fix the gate", author: "sam"),
        pr(2, "WIP", draft: true),
        pr(3, "queue churn", repo: "lessthanseventy/tlon")
      ],
      [pr(4, "Add exports")],
      [pr(5, "New settings"), pr(6, "bot PR", repo: "lessthanseventy/tlon")]
    )

    assert {:ok, proposals, []} = GitHub.fetch()

    assert [
             %{
               key: "https://github.com/acme/app/pull/1:review",
               text: "Review: Fix the gate",
               why: "acme/app#1, asked by sam",
               kind: "todo",
               url: "https://github.com/acme/app/pull/1"
             },
             %{key: "https://github.com/acme/app/pull/4:changes", text: "Changes requested: Add exports", kind: "todo"},
             %{
               key: "https://github.com/acme/app/pull/5:waiting",
               text: "Waiting on review: New settings",
               kind: "waiting",
               who: "a reviewer",
               done_text: "Reviewed: New settings"
             }
           ] = proposals

    assert_received {:gh,
                     [
                       "search",
                       "prs",
                       "--state=open",
                       "--draft=false",
                       "--limit",
                       "100",
                       "--json",
                       _,
                       "--review-requested=@me"
                     ]}

    assert_received {:gh, [_, _, _, _, _, _, _, _, "--author=@me", "--review=changes_requested"]}
    assert_received {:gh, [_, _, _, _, _, _, _, _, "--author=@me", "--review=none"]}
  end

  test "the poller files the waiting-on by itself, offers the rest, and says a PR reviewed as settled" do
    gh([pr(1, "Fix the gate")], [], [pr(5, "New settings")])
    modules = %{"github" => GitHub}
    Sources.poll("telegram", ["github"], modules, @now, %{})

    assert [%{text: "Review: Fix the gate"}] = Proposal.open()
    assert [%{text: "Waiting on review: New settings", waiting_on: "a reviewer"}] = Jot.waiting("telegram")

    gh([pr(1, "Fix the gate")], [pr(5, "New settings")], [])
    Sources.poll("telegram", ["github"], modules, DateTime.add(@now, 900), %{})

    assert Jot.waiting("telegram") == []
    assert [%{done_text: "Reviewed: New settings"}] = Proposal.settled()
    assert ["Review: Fix the gate", "Changes requested: New settings"] = Enum.map(Proposal.open(), & &1.text)
  end

  test "a review done elsewhere withdraws the open proposal, and a to-do he took stays" do
    modules = %{"github" => GitHub}
    gh([pr(1, "Fix the gate"), pr(2, "Add exports")], [], [])
    Sources.poll("telegram", ["github"], modules, @now, %{})
    [first, _second] = Proposal.open()
    {:ok, _} = Proposal.take("telegram", first.id, @now)

    gh([], [], [])
    Sources.poll("telegram", ["github"], modules, @now, %{})
    assert Proposal.open() == []
    assert [%{text: "Review: Fix the gate"}] = Jot.opens("telegram")
  end

  test "a failing source is logged once per distinct reason and leaves the proposals alone" do
    modules = %{"github" => GitHub}
    gh([pr(1, "Fix the gate")], [], [])
    Sources.poll("telegram", ["github"], modules, @now, %{})

    gh({:error, "gh exited 4"}, [], [])

    log =
      capture_log(fn ->
        failed = Sources.poll("telegram", ["github"], modules, @now, %{})
        assert failed == %{"github" => "gh exited 4"}
        failed = Sources.poll("telegram", ["github"], modules, @now, failed)
        gh({:error, "gh exited 1"}, [], [])
        Sources.poll("telegram", ["github"], modules, @now, failed)
      end)

    assert length(String.split(log, "home source github")) == 3
    assert log =~ "gh exited 4"
    assert log =~ "gh exited 1"
    assert [%{text: "Review: Fix the gate"}] = Proposal.open()
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

  test "home_sources names the sources: a comma list, empty for none" do
    assert Sources.names("github") == ["github"]
    assert Sources.names(" github, jira ,") == ["github", "jira"]
    assert Sources.names("") == []
  end
end
