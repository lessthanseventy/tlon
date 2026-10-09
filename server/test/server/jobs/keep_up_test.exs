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

  test "a failed or skipped check leaves an unowned repo's note" do
    KeepUp.drifted("/r/orphan", {:diverged, 3})
    KeepUp.drifted("/r/orphan", {:error, "x"})
    KeepUp.drifted("/r/orphan", :skipped)

    assert [_] = notes("/r/orphan")
  end
end
