defmodule Server.WorklineLandingTest do
  # Merged means merged: a landing published to GitHub waits, its thread open, until GitHub says
  # the PR is MERGED; only then is its thread closed, its ticket done and the issues it fixed resolved.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Jobs.KeepUp
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, name}), do: {:ok, "committed #{name}"}
    def check(_thread, :branch), do: {:ok, "work/x @ abc123"}
    def check(_thread, :checks), do: {:ok, "1 verify check_passed"}
  end

  defmodule Merges do
    @moduledoc false
    def merge(_repo, _slug, _opts \\ []), do: {:ok, %{from: "a", to: "b"}}
  end

  @url "https://github.com/o/r/pull/9"

  setup do
    Server.TestDB.clean!()
    :ok
  end

  # gh as GitHub would answer it: the PR opened at @url, and `gh pr view` saying `state`
  defp gh(state, over \\ %{}) do
    fn cmd, args, _opts ->
      send(self(), {:ran, [cmd | args]})
      pr = Map.merge(%{"state" => state, "mergeStateStatus" => "CLEAN", "statusCheckRollup" => []}, over)

      case {cmd, args} do
        {"gh", ["pr", "create" | _]} -> {@url <> "\n", 0}
        {"gh", ["pr", "merge" | _]} -> Map.get(over, :merge, {"", 0})
        {"gh", ["pr", "view" | _]} -> {Jason.encode!(Map.drop(pr, [:merge])), 0}
        _ -> {"", 0}
      end
    end
  end

  # a workline at review with a ticket that owns an open issue, landed by the merge queue and published
  defp published!(run \\ gh("OPEN")) do
    {:ok, ws} = Server.Workspaces.register(%{name: "Lit"})
    {:ok, thread} = Workline.open(%{title: "lamp", slug: "lamp", stage: "review", workspace_id: ws.id})
    {:ok, ticket} = Server.Tickets.file(%{workspace_id: thread.workspace_id, title: "lamp"})
    {:ok, _} = Server.Tickets.promote(ticket, thread.id)
    {:ok, issue} = Server.Dossier.raise_issue(%{summary: "the lamp is out"})
    {:ok, _} = Server.Dossier.own_issue(issue, ticket, "filed by tertius")

    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, queued} = parked |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    {:ok, landed} =
      Workline.land_queued(queued, merge: Merges, gate: fn _, _ -> {:ok, :green} end, run: run)

    %{thread: landed, ticket: ticket, issue: issue}
  end

  test "published: merged at the gate, but its thread stays open, its ticket not done, its issues open" do
    %{thread: t, ticket: ticket, issue: issue} = published!()

    assert_received {:ran, ["gh", "pr", "create" | _]}
    assert %Thread{stage: "merged", state: "open"} = Repo.get!(Thread, t.id)
    refute Server.Tickets.get(ticket.id).status == "done"
    assert %{state: "open"} = Repo.get!(Server.Issue, issue.id)
    assert Workline.landed_since(DateTime.add(DateTime.utc_now(), -60)) == []
    assert Enum.any?(Server.Channel.thread_messages(t), &(&1.body =~ @url and &1.body =~ "GitHub"))
  end

  test "GitHub says MERGED: closed, ticket done, issues resolved naming the PR, one landed toast" do
    %{thread: t, ticket: ticket, issue: issue} = published!()
    since = DateTime.add(DateTime.utc_now(), -60)

    KeepUp.landings(gh("MERGED"))
    KeepUp.landings(gh("MERGED"))

    assert_received {:ran, ["gh", "pr", "view", @url | _]}
    assert %Thread{stage: "merged", state: "closed"} = Repo.get!(Thread, t.id)
    assert Server.Tickets.get(ticket.id).status == "done"
    assert %{state: "closed", resolution: "fixed by " <> @url} = Repo.get!(Server.Issue, issue.id)
    assert [%{thread_id: tid}] = Workline.landed_since(since)
    assert tid == t.id
    assert [%{kind: "landed"}] = Server.Alerts.build([], [], DateTime.utc_now(), landed: Workline.landed_since(since))
  end

  test "GitHub still has it open: nothing changes" do
    %{thread: t, ticket: ticket} = published!()

    KeepUp.landings(gh("OPEN"))

    assert %Thread{state: "open"} = Repo.get!(Thread, t.id)
    refute Server.Tickets.get(ticket.id).status == "done"
  end

  test "nothing waits on GitHub: gh is not asked" do
    KeepUp.landings(gh("MERGED"))
    refute_received {:ran, _}
  end

  # a workline at review landed by the merge queue whose publish failed: gh would not open its PR
  defp publish_failed! do
    {:ok, ws} = Server.Workspaces.register(%{name: "Unlit"})
    {:ok, thread} = Workline.open(%{title: "wick", slug: "wick", stage: "review", workspace_id: ws.id})
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, queued} = parked |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    refusing = fn
      "gh", ["pr", "create" | _], _ -> {"no permission", 1}
      _, _, _ -> {"", 0}
    end

    {:ok, landed} = Workline.land_queued(queued, merge: Merges, gate: fn _, _ -> {:ok, :green} end, run: refusing)
    assert [_] = publish_failed(landed)
    assert Workline.waiting_on_github() == []
    Repo.get!(Thread, landed.id)
  end

  defp publish_failed(t),
    do: Enum.filter(Server.Office.Needs.list(), &(&1.kind == "publish_failed" and &1.thread_id == t.id))

  test "republished after a failed publish: it waits on GitHub, and closes when GitHub says MERGED" do
    t = publish_failed!()

    assert {:ok, @url} = Workline.republish(t, gh("OPEN"))

    assert publish_failed(t) == []
    assert [%{thread: %{id: id}, url: @url}] = Workline.waiting_on_github()
    assert id == t.id

    KeepUp.landings(gh("MERGED"))
    assert %Thread{stage: "merged", state: "closed"} = Repo.get!(Thread, t.id)
  end

  test "its PR opened by hand: the url put in is its landing, polled until GitHub says MERGED" do
    t = publish_failed!()
    assert [need] = publish_failed(t)

    assert [%{actions: actions}] = Server.Alerts.build([need], [], DateTime.utc_now())
    by_hand = Enum.find(actions, &(&1[:input] == "url"))
    assert by_hand.path == "/api/threads/#{t.id}/published"

    assert {:error, _} = Workline.published_by_hand(t, "  ")
    assert {:ok, _} = Workline.published_by_hand(t, @url)

    assert publish_failed(t) == []
    assert [%{url: @url}] = Workline.waiting_on_github()
    assert {:error, _} = Workline.published_by_hand(t, @url)

    KeepUp.landings(gh("MERGED"))
    assert %Thread{stage: "merged", state: "closed"} = Repo.get!(Thread, t.id)
  end

  describe "a landing GitHub isn't merging is a pr_blocked Need, with its answers" do
    defp blocked do
      Enum.filter(Server.Office.Needs.list(), &(&1.kind == "pr_blocked"))
    end

    defp answers(need), do: [need] |> Server.Alerts.build([], DateTime.utc_now()) |> hd() |> Map.fetch!(:actions)

    test "published and waiting, inside the hour: not a Need" do
      published!()

      KeepUp.landings(
        gh("OPEN", %{"mergeStateStatus" => "BLOCKED", "statusCheckRollup" => [%{"status" => "IN_PROGRESS"}]})
      )

      assert blocked() == []
    end

    test "auto-merge refused" do
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed for this repository", 1}}))

      assert [%{thread_id: tid, level: "blocking", text: text, url: @url} = need] = blocked()
      assert tid == t.id and text =~ "auto-merge is not allowed"
      assert [_ | _] = answers(need)
    end

    test "republished with auto-merge refused: published, so pr_blocked and no longer publish_failed" do
      t = publish_failed!()

      assert {:auto_refused, @url, _} = Workline.republish(t, gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))

      assert publish_failed(t) == []
      assert [%{thread_id: tid, url: @url}] = blocked()
      assert tid == t.id
    end

    test "GitHub reports it BLOCKED with nothing left running" do
      %{thread: t} = published!()

      KeepUp.landings(gh("OPEN", %{"mergeStateStatus" => "BLOCKED"}))
      KeepUp.landings(gh("OPEN", %{"mergeStateStatus" => "BLOCKED"}))

      assert [%{thread_id: tid, text: text} = need] = blocked()
      assert tid == t.id and text =~ "BLOCKED"
      assert [_ | _] = answers(need)
    end

    test "pending past an hour" do
      %{thread: t} = published!()
      hour_ago = DateTime.utc_now() |> DateTime.add(-3700) |> DateTime.truncate(:second)
      Repo.update_all(from(e in Server.Event, where: e.thread_id == ^t.id), set: [created_at: hour_ago])

      assert [%{thread_id: tid, text: text} = need] = blocked()
      assert tid == t.id and text =~ "hour"
      assert [_ | _] = answers(need)
    end

    test "its answers: rebase it, close and reland it, show me the PR" do
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))
      [need] = blocked()

      assert [
               %{label: "Rebase", method: "POST", path: rebase},
               %{label: "Close and reland", method: "POST", path: reland},
               %{label: "Show me", open: @url}
             ] = answers(need)

      assert rebase == "/api/threads/#{t.id}/rebase" and reland == "/api/threads/#{t.id}/reland"
    end

    test "rebase: GitHub rebases it and auto-merge is armed; the Need goes until the clock or GitHub says otherwise" do
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))

      assert {:ok, _} = Workline.rebase_landing(Repo.get!(Thread, t.id), gh("OPEN"))
      assert_received {:ran, ["gh", "pr", "update-branch", @url, "--rebase"]}
      assert blocked() == []
    end

    test "close and reland: its PR closed, the workline back at build on its branch" do
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))

      assert {:error, {:bounced, _}} = Workline.reland_landing(Repo.get!(Thread, t.id), gh("OPEN"))
      assert_received {:ran, ["gh", "pr", "close", @url | _]}
      assert %Thread{stage: "build", state: "open"} = Repo.get!(Thread, t.id)
      assert blocked() == []
    end

    test "a thread not waiting on GitHub has nothing to rebase or reland" do
      {:ok, t} = Workline.open(%{title: "x", slug: "x", stage: "build"})
      assert {:error, :not_landing} = Workline.rebase_landing(t, gh("OPEN"))
      assert {:error, :not_landing} = Workline.reland_landing(t, gh("OPEN"))
    end
  end

  describe "one answer to \"is it landing?\": waiting on GitHub, which the office's card reads" do
    defp landing?(t), do: Enum.find(Server.Office.status().threads, &(&1.id == t.id)).landing

    test "published and waiting: the office draws it as landing" do
      %{thread: t} = published!()
      assert landing?(t)
    end

    test "merged, then reopened by an operator reply: not landing, and not merged again" do
      %{thread: t} = published!()
      since = DateTime.add(DateTime.utc_now(), -60)
      KeepUp.landings(gh("MERGED"))

      Server.Attention.respond(t.id, "andrew", "one more thing about this")
      assert %Thread{stage: "merged", state: "open"} = Repo.get!(Thread, t.id)
      refute landing?(t)

      flush_ran()
      KeepUp.landings(gh("MERGED"))
      refute_received {:ran, _}
      assert %Thread{state: "open"} = Repo.get!(Thread, t.id)
      assert [_one] = Workline.landed_since(since)
    end
  end

  defp flush_ran do
    receive do
      {:ran, _} -> flush_ran()
    after
      0 -> :ok
    end
  end
end
