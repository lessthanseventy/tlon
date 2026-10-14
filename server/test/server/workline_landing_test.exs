defmodule Server.WorklineLandingTest do
  # Merged means merged: a landing published to GitHub waits, its thread open, until GitHub says
  # the PR is MERGED; only then is its thread closed, its ticket done and the issues it fixed resolved.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

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

  # main moved: the rebase gives a new head, which the gate it is handed runs on
  defmodule RebasesOnto do
    @moduledoc false
    def merge(repo, slug, opts) do
      {:ok, :green} = opts[:gate].(repo, "work/#{slug}")
      {:ok, %{from: "m2", to: "c2"}}
    end
  end

  defmodule Conflicts do
    @moduledoc false
    def merge(_repo, slug, _opts), do: {:error, "work/#{slug} conflicts with origin/main in lib/lamp.ex"}
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
    assert_received {:ran, ["gh", "api", "repos/{owner}/{repo}/statuses/b" | _]}
    assert_received {:ran, ["gh", "pr", "merge", @url, "--rebase", "--match-head-commit", "b"]}
    assert_received {:ran, ["gh", "api", "-X", "DELETE", "repos/{owner}/{repo}/git/refs/heads/work/lamp"]}
    refute_received {:ran, ["gh", "pr", "merge", _, "--rebase", "--auto" | _]}
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
    refute_received {:ran, ["gh", "api" | _]}

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

    test "behind main: back in the merge queue on its own, no Need and no GitHub rebase" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!()

      KeepUp.landings(gh("OPEN", %{"mergeStateStatus" => "BEHIND", "headRefOid" => "h1"}))

      assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: t.id, reland: true, auto: true})
      refute_received {:ran, ["gh", "pr", "update-branch" | _]}
      assert blocked() == []
    end

    test "a conflict after an automatic requeue is the Need, the PR left open for the operator" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!()
      KeepUp.landings(gh("OPEN", %{"mergeStateStatus" => "BEHIND", "headRefOid" => "h1"}))
      flush_ran()

      assert {:error, _} =
               Workline.reland_queued(Repo.get!(Thread, t.id), merge: Conflicts, run: gh("OPEN"), auto: true)

      ran_out!()

      assert [%{thread_id: tid, text: text}] = blocked()
      assert tid == t.id and text =~ "conflicts with origin/main"
      refute_received {:ran, ["gh", "pr", "close" | _]}
      assert %Thread{stage: "merged", state: "open"} = Repo.get!(Thread, t.id)
    end

    test "BLOCKED again at a head it was already requeued at: the Need, not a second requeue" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!()
      held = gh("OPEN", %{"mergeStateStatus" => "BLOCKED", "headRefOid" => "h1"})

      KeepUp.landings(held)
      assert blocked() == []
      ran_out!()

      KeepUp.landings(held)

      assert [%{thread_id: tid, text: text} = need] = blocked()
      assert tid == t.id and text =~ "BLOCKED"
      assert [_ | _] = answers(need)
      assert Repo.aggregate(from(j in Oban.Job, where: j.worker == "Server.Jobs.Land"), :count) == 1
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

    test "rebase: back in the merge queue as a landing; GitHub neither rebases it nor arms auto-merge" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))
      flush_ran()

      assert {:ok, _} = Workline.rebase_landing(Repo.get!(Thread, t.id))
      assert_enqueued(worker: Server.Jobs.Land, args: %{thread_id: t.id, reland: true})
      refute_received {:ran, ["gh", "pr", "update-branch" | _]}
      refute_received {:ran, ["gh", "pr", "merge", _, "--rebase", "--auto" | _]}
      assert blocked() == []
    end

    test "the requeued landing rebases and gates it, posts tlon/check on the gated sha and merges at that head" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))
      {:ok, _} = Workline.rebase_landing(Repo.get!(Thread, t.id))
      flush_ran()

      assert {:ok, _} =
               Workline.reland_queued(Repo.get!(Thread, t.id),
                 merge: RebasesOnto,
                 gate: fn _, _ ->
                   send(self(), :gated)
                   {:ok, :green}
                 end,
                 run: gh("OPEN")
               )

      assert_received :gated
      assert_received {:ran, ["git", _, _, "push", "--force-with-lease", "origin", "work/lamp"]}
      assert_received {:ran, ["gh", "api", "repos/{owner}/{repo}/statuses/c2" | _]}
      assert_received {:ran, ["gh", "pr", "merge", @url, "--rebase", "--match-head-commit", "c2"]}
      refute_received {:ran, ["gh", "pr", "update-branch" | _]}
      refute_received {:ran, ["gh", "pr", "merge", _, "--rebase", "--auto" | _]}
      assert %Thread{stage: "merged", state: "open"} = Repo.get!(Thread, t.id)
      assert blocked() == []
    end

    test "a requeued landing a rebase can't resolve is refused on the thread: its PR closed, back at build" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))
      {:ok, _} = Workline.rebase_landing(Repo.get!(Thread, t.id))
      flush_ran()

      assert {:error, {:bounced, why}} =
               Workline.reland_queued(Repo.get!(Thread, t.id), merge: Conflicts, run: gh("OPEN"))

      assert why =~ "conflicts with origin/main"
      assert_received {:ran, ["gh", "pr", "close", @url | _]}
      refute_received {:ran, ["gh", "pr", "merge" | _]}
      assert %Thread{stage: "build", state: "open"} = Repo.get!(Thread, t.id)
      assert Enum.any?(Server.Channel.thread_messages(t), &(&1.body =~ "conflicts with origin/main"))
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
      assert {:error, :not_landing} = Workline.rebase_landing(t)
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

  # the queued landing's turn came and went
  defp ran_out!, do: Repo.update_all(Oban.Job, set: [state: "completed"])

  defp flush_ran do
    receive do
      {:ran, _} -> flush_ran()
    after
      0 -> :ok
    end
  end
end
