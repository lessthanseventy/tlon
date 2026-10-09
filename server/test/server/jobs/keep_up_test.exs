defmodule Server.Jobs.KeepUpTest do
  # A drifted local main is one note per repo, routed to the workspace whose project owns it.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Jobs.KeepUp
  alias Server.Message
  alias Server.Repo
  alias Server.Rollout
  alias Server.Tickets
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    for n <- Rollout.pending(), do: Rollout.dismiss(n.id)
    # the notes live in the Rollout process, not the db: left behind they are the next test's rollout items
    on_exit(fn -> for n <- Rollout.pending(), do: Rollout.dismiss(n.id) end)
    :ok
  end

  defp notes(repo), do: Enum.filter(Rollout.pending(), &String.contains?(&1.text, repo))

  describe "a repo no project owns" do
    test "two checks with different counts leave one note, carrying the latest" do
      KeepUp.drifted("/r/orphan", {:diverged, 15})
      KeepUp.drifted("/r/orphan", {:diverged, 16})

      assert [%{text: text}] = notes("/r/orphan")
      assert text =~ "16 commit"
    end

    test "main level again clears it" do
      KeepUp.drifted("/r/orphan", {:diverged, 3})
      KeepUp.drifted("/r/orphan", :forwarded)

      assert notes("/r/orphan") == []
    end
  end

  describe "a repo a project owns" do
    setup do
      {:ok, _root} = Workspaces.create(%{name: "Home"})
      {:ok, ws} = Workspaces.create(%{name: "Three"})

      {:ok, _} =
        Server.Projects.register(%{workspace_id: ws.id, name: "p", repos: [%{"name" => "p", "path" => "/r/owned"}]})

      %{ws: ws, lobby: Server.Channel.machine_thread(ws.id)}
    end

    test "posts on that workspace's lobby, not the root, and the operator hears nothing", %{ws: ws, lobby: lobby} do
      KeepUp.drifted("/r/owned", {:diverged, 4})

      assert [%Message{body: body}] =
               Repo.all(from m in Message, where: m.thread_id == ^lobby.id and m.author == "tlon")

      assert body =~ "/r/owned" and body =~ "4 commit"
      assert [] = Repo.all(from m in Message, where: m.thread_id != ^lobby.id and m.author == "tlon")
      assert notes("/r/owned") == []
      assert [%{title: "land local main's 4 commits"}] = Tickets.open_in_workspace(ws.id)
    end

    test "a later count updates the one ticket and does not post again", %{ws: ws, lobby: lobby} do
      KeepUp.drifted("/r/owned", {:diverged, 4})
      KeepUp.drifted("/r/owned", {:diverged, 6})

      assert [%{title: "land local main's 6 commits"}] = Tickets.open_in_workspace(ws.id)
      assert [_one] = Repo.all(from m in Message, where: m.thread_id == ^lobby.id and m.author == "tlon")
    end

    test "no lobby to post on falls back to the keyed operator note", %{ws: ws, lobby: lobby} do
      Repo.delete_all(from m in Message, where: m.thread_id == ^lobby.id)
      Repo.delete!(lobby)

      KeepUp.drifted("/r/owned", {:diverged, 4})
      KeepUp.drifted("/r/owned", {:diverged, 5})

      assert [%{text: text}] = notes("/r/owned")
      assert text =~ "5 commit"
      assert [_] = Tickets.open_in_workspace(ws.id)
    end

    test "main level again closes the ticket", %{ws: ws} do
      KeepUp.drifted("/r/owned", {:diverged, 4})
      KeepUp.drifted("/r/owned", :forwarded)

      assert Tickets.open_in_workspace(ws.id) == []
    end

    test "a failed or skipped check changes nothing", %{ws: ws} do
      KeepUp.drifted("/r/owned", {:diverged, 4})
      KeepUp.drifted("/r/owned", {:error, "fetch failed"})
      KeepUp.drifted("/r/owned", :skipped)

      assert [%{title: "land local main's 4 commits"}] = Tickets.open_in_workspace(ws.id)
    end
  end

  describe "a landed workline whose PR's checks went red" do
    setup do
      {:ok, ws} = Workspaces.register(%{name: "Watched"})
      {:ok, _} = Workspaces.seat(ws.id, %{name: "scharlach", archetype: "sheriff"})
      {:ok, t} = Server.Workline.open(%{title: "lamp", slug: "lamp", stage: "review", workspace_id: ws.id})
      Repo.update_all(from(x in Server.Thread, where: x.id == ^t.id), set: [stage: "merged"])
      %{thread: t}
    end

    defp gh(prs) do
      fn cmd, args, _opts ->
        send(self(), {:ran, [cmd | args]})

        case args do
          ["pr", "list" | _] -> {Jason.encode!(prs), 0}
          _ -> {"", 0}
        end
      end
    end

    @red [%{"number" => 9, "headRefName" => "work/lamp", "statusCheckRollup" => [%{"conclusion" => "FAILURE"}]}]

    test "is reported to the sheriff, its PR closed and the workline back at build", %{thread: t} do
      KeepUp.red_checks("/repo", gh(@red))

      assert_received {:ran, ["gh", "pr", "close", "9", "--comment", comment]}
      assert comment =~ "checks"
      assert %Server.Thread{stage: "build", state: "open"} = Repo.get!(Server.Thread, t.id)

      beat =
        Repo.one!(from b in Server.Thread, where: b.workspace_id == ^t.workspace_id and b.title == "sheriff's beat")

      assert [%Message{body: body}] = Repo.all(from m in Message, where: m.thread_id == ^beat.id and like(m.body, "🚨%"))
      assert body =~ "PR #9" and body =~ "red"
    end

    test "a PR that will not close is not reported, so the next tick does not repeat the report", %{thread: t} do
      run = fn cmd, args, _opts ->
        case args do
          ["pr", "list" | _] -> {Jason.encode!(@red), 0}
          ["pr", "close" | _] -> {"gh: boom", 1}
          _ -> {cmd, 0}
        end
      end

      KeepUp.red_checks("/repo", run)

      assert %Server.Thread{stage: "merged"} = Repo.get!(Server.Thread, t.id)
      assert [] = Repo.all(from m in Message, where: like(m.body, "🚨%"))
    end

    test "a PR whose workline has not landed is left alone", %{thread: t} do
      Repo.update_all(from(x in Server.Thread, where: x.id == ^t.id), set: [stage: "review"])
      KeepUp.red_checks("/repo", gh(@red))

      refute_received {:ran, ["gh", "pr", "close" | _]}
      assert %Server.Thread{stage: "review"} = Repo.get!(Server.Thread, t.id)
    end
  end

  test "a failed or skipped check leaves an unowned repo's note" do
    KeepUp.drifted("/r/orphan", {:diverged, 3})
    KeepUp.drifted("/r/orphan", {:error, "x"})
    KeepUp.drifted("/r/orphan", :skipped)

    assert [_] = notes("/r/orphan")
  end
end
