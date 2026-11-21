defmodule Server.Projects.RemovalTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.{Channel, Projects, Repo, Rollout, Thread, Workspaces}

  setup do
    Server.TestDB.clean!()
    :ok
  end

  defp stamp, do: "#{System.pid()}-#{System.unique_integer([:positive])}"

  defp gone_workspace(name) do
    path = Path.join(System.tmp_dir!(), "gone-#{stamp()}")
    {:ok, ws} = Workspaces.create(%{name: name, repos: [path]})
    project = Projects.default(ws.id)
    desk = Channel.machine_thread(ws.id)

    {:ok, memory} =
      Repo.insert(%Thread{
        title: Server.Import.Memory.thread_title(),
        state: "closed",
        scope: "machine",
        workspace_id: ws.id,
        project_id: project.id,
        created_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

    %{ws: ws, project: project, desk: desk, memory: memory, path: path}
  end

  defp counts do
    for table <- ~w(project workspace thread workspace_repo channel), into: %{} do
      {table, Repo.one(from r in table, select: count())}
    end
  end

  defp sync, do: Rollout.pending()

  describe "a project with only its born-with scaffolding" do
    test "a dry run reads, a removal deletes project, threads, repo rows, channel and workspace in one go" do
      %{ws: ws, project: project, desk: desk, memory: memory, path: path} = gone_workspace("gone")
      Server.Bus.subscribe_projects()
      Server.Bus.subscribe_workspaces()
      before = counts()

      assert {:ok, plan} = Projects.remove_with_empties("gone", :dry_run)
      assert plan.drop_workspace
      assert Enum.sort(Enum.map(plan.threads, & &1.id)) == Enum.sort([desk.id, memory.id])
      assert [%{path: ^path}] = plan.repos
      assert counts() == before

      assert {:ok, _} = Projects.remove_with_empties("gone", :remove)
      assert_receive {:project_removed, %{id: id}} when id == project.id
      assert_receive {:workspace_removed, %{id: wid}} when wid == ws.id

      assert %{"project" => p, "workspace" => w, "thread" => t, "workspace_repo" => r, "channel" => c} = counts()

      assert {p, w, t, r, c} ==
               {before["project"] - 1, before["workspace"] - 1, before["thread"] - 2, 0, before["channel"] - 1}

      assert {:error, :no_project} = Projects.remove_with_empties("gone", :remove)
      assert {:error, :no_project} = Projects.remove_with_empties("gone", :dry_run)
    end

    test "the keyed notes and keep rows of its repo go, another repo's stay" do
      %{path: path} = gone_workspace("gone")
      other = path <> "-other"
      Rollout.note("keep_up:gone:#{path}", "gone")
      Rollout.note("keep_up:warm:#{path}/server", "warm")
      Rollout.note("keep_up:gone:#{other}", "someone else's")
      Server.Home.Keep.put("keep_up:warm:#{path}/server", "abc ok")
      Server.Home.Keep.put("keep_up:warm:#{other}", "abc ok")
      sync()

      assert {:ok, plan} = Projects.remove_with_empties("gone", :dry_run)
      assert Enum.sort(plan.notes) == ["keep_up:gone:#{path}", "keep_up:warm:#{path}/server"]
      assert plan.keep == ["keep_up:warm:#{path}/server"]
      assert Server.Home.Keep.get("keep_up:warm:#{path}/server") == "abc ok"

      assert {:ok, _} = Projects.remove_with_empties("gone", :remove)
      assert [%{key: key}] = Enum.filter(Rollout.pending(), &String.contains?(&1.text, "someone"))
      assert key == "keep_up:gone:#{other}"
      refute Enum.any?(Rollout.pending(), &(String.contains?(&1.key, path <> "/") or &1.key == "keep_up:gone:#{path}"))
      assert Server.Home.Keep.get("keep_up:warm:#{path}/server") == nil
      assert Server.Home.Keep.get("keep_up:warm:#{other}") == "abc ok"
    end
  end

  describe "what carries work holds the removal and nothing is deleted" do
    for {label, reason} <- [
          message: "holds 1 messages",
          session: "holds 1 sessions",
          wake: "holds 1 queued wakes",
          fact: "holds 1 facts",
          workline: "carries workline state (stage build",
          child: "is not one of its two born-with threads",
          other_agent: "not the workspace's lead",
          ticket: "project holds 1 tickets",
          jot: "project holds 1 jots",
          bench: "workspace holds 1 bench seats",
          topic: "workspace holds 1 topic channels"
        ] do
      test "#{label}" do
        %{ws: ws, project: project, desk: desk, memory: memory} = gone_workspace("held")
        hold(unquote(label), ws, project, desk, memory)
        before = counts()

        for mode <- [:dry_run, :remove] do
          assert {:error, {:blocked, reasons}} = Projects.remove_with_empties("held", mode)
          assert Enum.any?(reasons, &String.contains?(&1, unquote(reason)))
        end

        assert counts() == before
      end
    end
  end

  defp hold(:message, _ws, _p, desk, _memory),
    do: {:ok, _} = Channel.post(%{thread_id: desk.id, author: "andrew", body: "hi"})

  defp hold(:session, _ws, _p, desk, _memory) do
    {:ok, agent} = Server.Staff.register_agent(%{name: "a-#{stamp()}", mandate: "m", engine: "claude"})
    {:ok, _} = Server.Staff.start_session(%{agent_id: agent.id, thread_id: desk.id})
  end

  defp hold(:wake, _ws, _p, desk, _memory), do: {:ok, _} = Server.Wake.queue(desk.id, "a", "p")

  defp hold(:fact, _ws, _p, _desk, memory) do
    {:ok, _} =
      Server.Dossier.bank_fact(%{
        thread_id: memory.id,
        text: "the build needs the flag",
        kind: "learned",
        provenance: "stated"
      })
  end

  defp hold(:workline, _ws, _p, _desk, memory),
    do: Repo.update_all(from(t in Thread, where: t.id == ^memory.id), set: [stage: "build"])

  defp hold(:child, ws, p, desk, _memory) do
    {:ok, _} = Channel.open_thread(%{title: "child", workspace_id: ws.id, project_id: p.id, parent_thread_id: desk.id})
  end

  defp hold(:other_agent, _ws, _p, _desk, memory) do
    {:ok, agent} = Server.Staff.register_agent(%{name: "b-#{stamp()}", mandate: "m", engine: "claude"})
    Repo.update_all(from(t in Thread, where: t.id == ^memory.id), set: [agent_id: agent.id])
  end

  defp hold(:ticket, ws, p, _desk, _memory),
    do: {:ok, _} = Server.Tickets.file(%{workspace_id: ws.id, project_id: p.id, title: "t"})

  defp hold(:jot, _ws, p, _desk, _memory) do
    {1, _} =
      Repo.insert_all("jot", [
        %{
          via: "t",
          external_id: 1,
          body: "b",
          received_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second),
          project_id: p.id
        }
      ])
  end

  defp hold(:bench, ws, _p, _desk, _memory),
    do: {:ok, _} = Workspaces.seat(ws.id, %{name: "w-#{stamp()}", archetype: "builder"})

  defp hold(:topic, ws, _p, _desk, _memory), do: {:ok, _} = Server.Channels.create(ws.id, "topic")

  describe "a workspace that holds another project" do
    test "stays, with its standing thread moved to the default among the others" do
      %{ws: ws, project: project, desk: desk, memory: memory, path: path} = gone_workspace("shared")
      other_path = path <> "-other"
      {:ok, _} = Workspaces.add_repo(ws.id, %{path: other_path})

      {:ok, keep} =
        Projects.register(%{workspace_id: ws.id, name: "keeps", repos: [%{"name" => "k", "path" => other_path}]})

      before = counts()

      assert {:ok, plan} = Projects.remove_with_empties("shared", :dry_run)
      refute plan.drop_workspace
      assert {^desk, %{id: keep_id}} = plan.repoint
      assert keep_id == keep.id
      assert counts() == before

      assert {:ok, _} = Projects.remove_with_empties("shared", :remove)
      assert Workspaces.get(ws.id)
      assert Projects.get(project.id) == nil
      assert Repo.get(Thread, memory.id) == nil
      assert Repo.get(Thread, desk.id).project_id == keep.id
      assert Workspaces.get(ws.id).default_project_id == keep.id
      assert [%{path: ^other_path}] = Workspaces.repos(ws.id)
      assert Channel.machine_thread(ws.id).id == desk.id
    end

    test "a message on the standing thread does not hold it" do
      %{ws: ws, desk: desk, path: path} = gone_workspace("shared")

      {:ok, _} =
        Projects.register(%{workspace_id: ws.id, name: "keeps", repos: [%{"name" => "k", "path" => path <> "-o"}]})

      {:ok, _} = Channel.post(%{thread_id: desk.id, author: "andrew", body: "hi"})

      assert {:ok, _} = Projects.remove_with_empties("shared", :remove)
      assert Repo.get(Thread, desk.id)
    end
  end

  test "a name two workspaces share is refused as ambiguous" do
    gone_workspace("twin")
    other = gone_workspace("other")
    {:ok, _} = Projects.register(%{workspace_id: other.ws.id, name: "twin", repos: []})
    before = counts()

    assert {:error, {:ambiguous, names}} = Projects.remove_with_empties("twin", :remove)
    assert Enum.sort(names) == ["other", "twin"]
    assert counts() == before
  end

  describe "Server.CLI.project_remove/2" do
    test "says what it would remove, removes with yes, then has no such project" do
      %{path: path} = gone_workspace("gone")

      assert {:ok, text} = Server.CLI.project_remove("gone", false)

      assert text == """
             dry run, nothing changed (add --yes to remove), project "gone" would remove:
               project gone (workspace gone)
               thread #{thread_line(text, "the front desk")}
               thread #{thread_line(text, "Claude Code memory")}
               workspace repo #{path}
               workspace gone (its last project)\
             """

      assert {:ok, "removed with project \"gone\":" <> _} = Server.CLI.project_remove("gone", true)
      assert {:error, ~s(no project named "gone")} = Server.CLI.project_remove("gone", true)
    end

    test "names what holds it" do
      %{desk: desk} = gone_workspace("held")
      {:ok, _} = Channel.post(%{thread_id: desk.id, author: "andrew", body: "hi"})

      assert {:error, text} = Server.CLI.project_remove("held", true)
      assert text =~ ~s(refused: project "held" is held by:\n  - thread #)
      assert text =~ ~s("the front desk" holds 1 messages)
      assert String.ends_with?(text, "\nnothing removed")
    end
  end

  defp thread_line(text, title) do
    [id] = Regex.run(~r/thread (#\d+) "#{title}"/, text, capture: :all_but_first)
    ~s(#{id} "#{title}")
  end
end
