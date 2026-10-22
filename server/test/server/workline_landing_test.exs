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

    test "a requeued landing fetches work/<slug> before its lease, so a head GitHub moved doesn't refuse the push" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))
      {:ok, _} = Workline.rebase_landing(Repo.get!(Thread, t.id))
      flush_ran()
      github = gh("OPEN")

      # GitHub moved work/lamp's head: the lease holds only once the tracking ref is fetched
      run = fn
        "git", [_, _, "fetch", "origin", "+refs/heads/work/lamp:refs/remotes/origin/work/lamp"] = args, _opts ->
          send(self(), {:ran, ["git" | args]})
          Process.put(:fetched, true)
          {"", 0}

        "git", [_, _, "push", "--force-with-lease" | _] = args, _opts ->
          send(self(), {:ran, ["git" | args]})
          if Process.get(:fetched), do: {"", 0}, else: {"! [rejected] work/lamp (stale info)", 1}

        cmd, args, opts ->
          github.(cmd, args, opts)
      end

      assert {:ok, _} =
               Workline.reland_queued(Repo.get!(Thread, t.id),
                 merge: RebasesOnto,
                 gate: fn _, _ -> {:ok, :green} end,
                 run: run
               )

      assert_received {:ran, ["gh", "pr", "merge", @url, "--rebase", "--match-head-commit", "c2"]}
      assert blocked() == []
    end

    test "a requeued landing GitHub only armed auto-merge for is not requeued again at that head" do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{thread: t} = published!(gh("OPEN", %{merge: {"auto-merge is not allowed", 1}}))
      {:ok, _} = Workline.rebase_landing(Repo.get!(Thread, t.id))
      ran_out!()
      expected = {~s(Required status check "tlon/check" is expected), 1}
      github = gh("OPEN", %{merge: expected})

      run = fn
        "gh", ["pr", "merge", _, "--rebase", "--auto" | _] = args, _opts ->
          send(self(), {:ran, ["gh" | args]})
          {"", 0}

        cmd, args, opts ->
          github.(cmd, args, opts)
      end

      assert {:ok, _} =
               Workline.reland_queued(Repo.get!(Thread, t.id),
                 merge: RebasesOnto,
                 gate: fn _, _ -> {:ok, :green} end,
                 run: run
               )

      assert_received {:ran, ["gh", "pr", "merge", @url, "--rebase", "--auto", "--match-head-commit", "c2"]}

      KeepUp.landings(gh("OPEN", %{"mergeStateStatus" => "BLOCKED", "headRefOid" => "c2"}))

      refute_enqueued(worker: Server.Jobs.Land, args: %{thread_id: t.id})
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

    test "a gh that cannot be read blocks, closes and merges nothing: the landing waits as it was" do
      %{thread: t, ticket: ticket} = published!()
      waiting = Workline.waiting_on_github()

      down = fn cmd, args, _opts ->
        send(self(), {:ran, [cmd | args]})
        {"gh: HTTP 502", 1}
      end

      log = ExUnit.CaptureLog.capture_log(fn -> KeepUp.landings(down) end)

      assert log =~ "unread" and log =~ "HTTP 502"
      assert %Thread{stage: "merged", state: "open"} = Repo.get!(Thread, t.id)
      refute Server.Tickets.get(ticket.id).status == "done"
      assert Enum.map(Workline.waiting_on_github(), & &1.event.kind) == Enum.map(waiting, & &1.event.kind)
      refute Enum.any?(Workline.waiting_on_github(), &(&1.event.kind == "check_failed"))
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

  # a merge train's merger, answered from the test process: stack/3 green unless told otherwise,
  # merge/3 running the certify gate it is handed, tree/2 the train's own unless told otherwise
  defmodule Train do
    @moduledoc false
    def stack(_repo, slugs, _opts) do
      send(self(), {:stack, slugs})

      case Process.get(:stack_results, []) do
        [r | rest] ->
          Process.put(:stack_results, rest)
          r

        [] ->
          {:ok, %{from: "m", cars: Enum.map(slugs, &%{slug: &1, to: "to-#{&1}", tree: "tree-#{&1}"})}}
      end
    end

    def merge(repo, slug, opts) do
      send(self(), {:merge, slug})

      with {:ok, _} <- opts[:gate].(repo, "work/#{slug}"), do: {:ok, %{from: "m2", to: "re-#{slug}"}}
    end

    def tree(_repo, "work/" <> slug), do: Process.get({:tree, slug}, "tree-#{slug}")
  end

  defp queued!(slug) do
    {:ok, thread} = Workline.open(%{title: slug, slug: slug, stage: "review"})
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, queued} = parked |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()
    queued
  end

  describe "land_train/3" do
    test "two queued worklines ride one gate and both land, the second certified by its tree" do
      a = queued!("car-a")
      b = queued!("car-b")

      assert {:ok, _} = Workline.land_train(a, [b], merge: Train, gate: fn _, _ -> {:ok, :green} end, run: gh("OPEN"))

      assert_received {:stack, ["car-a", "car-b"]}
      refute_received {:stack, _}
      assert_received {:merge, "car-a"}
      assert_received {:merge, "car-b"}
      assert %Thread{stage: "merged"} = Repo.get!(Thread, a.id)
      assert %Thread{stage: "merged"} = Repo.get!(Thread, b.id)
      assert Enum.any?(Server.Channel.thread_messages(Repo.get!(Thread, a.id)), &(&1.body =~ "merge train"))
    end

    test "a red train is run again before it is believed; red twice, the lead lands alone and the rest wait" do
      a = queued!("red-a")
      b = queued!("red-b")
      Process.put(:stack_results, [{:error, {:gate, "red"}}, {:error, {:gate, "red"}}])

      assert {:ok, _} = Workline.land_train(a, [b], merge: Train, gate: fn _, _ -> {:ok, :green} end, run: gh("OPEN"))

      assert_received {:stack, _}
      assert_received {:stack, _}
      assert_received {:merge, "red-a"}
      refute_received {:merge, "red-b"}
      assert %Thread{stage: "merged"} = Repo.get!(Thread, a.id)
      assert %Thread{stage: "review"} = Repo.get!(Thread, b.id)
    end

    test "a car whose rebase onto the new main is not the tree the train gated waits for its own turn" do
      a = queued!("moved-a")
      b = queued!("moved-b")
      Process.put({:tree, "moved-b"}, "someone else's main under it")

      assert {:ok, _} = Workline.land_train(a, [b], merge: Train, gate: fn _, _ -> {:ok, :green} end, run: gh("OPEN"))

      assert %Thread{stage: "merged"} = Repo.get!(Thread, a.id)
      assert %Thread{stage: "review"} = Repo.get!(Thread, b.id)
    end

    test "a lead whose rebase onto main is not the tree the train gated lands alone, gated alone" do
      a = queued!("drift-a")
      b = queued!("drift-b")
      Process.put({:tree, "drift-a"}, "main moved while the train was gated")

      assert {:ok, _} = Workline.land_train(a, [b], merge: Train, gate: fn _, _ -> {:ok, :green} end, run: gh("OPEN"))

      assert_received {:merge, "drift-a"}
      assert_received {:merge, "drift-a"}
      refute_received {:merge, "drift-b"}
      assert %Thread{stage: "merged"} = Repo.get!(Thread, a.id)
      assert %Thread{stage: "review"} = Repo.get!(Thread, b.id)
    end

    test "the landing job's companions: queued landings first come first, never a reland, never itself" do
      a = queued!("job-a")
      b = queued!("job-b")
      c = queued!("job-c")
      lead = %{thread_id: a.id} |> Server.Jobs.Land.new() |> Repo.insert!()
      %{thread_id: c.id, reland: true} |> Server.Jobs.Land.new() |> Repo.insert!()
      %{thread_id: b.id} |> Server.Jobs.Land.new() |> Repo.insert!()

      assert [%Thread{id: id}] = Server.Jobs.Land.companions(a, lead.id)
      assert id == b.id
    end

    test "it tells on_cars which cars took the gate: the train, the lead alone when the rest can't ride, the lead split off when red twice" do
      cars = fn ids, split -> send(self(), {:cars, ids, split}) end
      green = fn _, _ -> {:ok, :green} end
      a = queued!("tell-a")
      b = queued!("tell-b")

      Workline.land_train(a, [b], merge: Train, gate: green, run: gh("OPEN"), on_cars: cars)
      assert_received {:cars, ids, false}
      assert ids == [a.id, b.id]

      c = queued!("tell-c")
      parked = Repo.update!(Thread.workline_stage_changeset(queued!("tell-d"), %{awaiting: "andrew"}))
      Workline.land_train(c, [parked], merge: Train, gate: green, run: gh("OPEN"), on_cars: cars)
      assert_received {:cars, ids, false}
      assert ids == [c.id]

      e = queued!("tell-e")
      f = queued!("tell-f")
      Process.put(:stack_results, [{:error, {:gate, "red"}}, {:error, {:gate, "red"}}])
      Workline.land_train(e, [f], merge: Train, gate: green, run: gh("OPEN"), on_cars: cars)
      assert_received {:cars, ids, false}
      assert ids == [e.id, f.id]
      assert_received {:cars, ids, true}
      assert ids == [e.id]
    end

    test "the landing job records the cars it took in its meta, keeping what was there" do
      a = queued!("meta-a")
      b = queued!("meta-b")
      job = %{thread_id: a.id} |> Server.Jobs.Land.new(meta: %{"kept" => 1}) |> Repo.insert!()

      Server.Jobs.Land.record_cars(job.id).([a.id, b.id], false)
      assert %{"cars" => [a_id, b_id], "split" => false, "kept" => 1} = Repo.get!(Oban.Job, job.id).meta
      assert [a_id, b_id] == [a.id, b.id]

      parked = Repo.update!(Thread.workline_stage_changeset(a, %{awaiting: "andrew"}))
      assert :ok = Server.Jobs.Land.perform(%{Repo.get!(Oban.Job, job.id) | attempt: 1})
      assert %{"cars" => [only], "split" => false} = Repo.get!(Oban.Job, job.id).meta
      assert only == parked.id
    end

    test "alone, it is land_queued" do
      a = queued!("solo")
      assert {:ok, _} = Workline.land_train(a, [], merge: Train, gate: fn _, _ -> {:ok, :green} end, run: gh("OPEN"))
      refute_received {:stack, _}
      assert %Thread{stage: "merged"} = Repo.get!(Thread, a.id)
    end
  end
end
