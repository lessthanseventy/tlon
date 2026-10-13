defmodule Server.WorklineLandingTest do
  # Merged means merged: a landing published to GitHub waits, its thread open, until GitHub says
  # the PR is MERGED; only then is its thread closed, its ticket done and the issues it fixed resolved.
  use ExUnit.Case, async: false

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
  defp gh(state) do
    fn cmd, args, _opts ->
      send(self(), {:ran, [cmd | args]})

      case {cmd, args} do
        {"gh", ["pr", "create" | _]} -> {@url <> "\n", 0}
        {"gh", ["pr", "view" | _]} -> {Jason.encode!(%{"state" => state, "mergeStateStatus" => "CLEAN"}), 0}
        _ -> {"", 0}
      end
    end
  end

  # a workline at review with a ticket that owns an open issue, landed by the merge queue and published
  defp published! do
    {:ok, ws} = Server.Workspaces.register(%{name: "Lit"})
    {:ok, thread} = Workline.open(%{title: "lamp", slug: "lamp", stage: "review", workspace_id: ws.id})
    {:ok, ticket} = Server.Tickets.file(%{workspace_id: thread.workspace_id, title: "lamp"})
    {:ok, _} = Server.Tickets.promote(ticket, thread.id)
    {:ok, issue} = Server.Dossier.raise_issue(%{summary: "the lamp is out"})
    {:ok, _} = Server.Dossier.own_issue(issue, ticket, "filed by tertius")

    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    {:ok, queued} = parked |> Thread.workline_stage_changeset(%{awaiting: nil}) |> Repo.update()

    {:ok, landed} =
      Workline.land_queued(queued, merge: Merges, gate: fn _, _ -> {:ok, :green} end, run: gh("OPEN"))

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
