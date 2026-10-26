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

  test "a repo whose pass raises (gh not on PATH) fails the job: a failed job the operator sees, not only a log line" do
    {:ok, ws} = Workspaces.create(%{name: "Broken"})

    {:ok, _} =
      Server.Projects.register(%{workspace_id: ws.id, name: "b", repos: [%{"name" => "b", "path" => "/r/nowhere"}]})

    path = System.get_env("PATH")
    System.put_env("PATH", "")

    {result, log} =
      try do
        ExUnit.CaptureLog.with_log(fn -> KeepUp.perform(%Oban.Job{}) end)
      after
        System.put_env("PATH", path)
      end

    assert {:error, why} = result
    assert why =~ "/r/nowhere"
    assert log =~ "keep_up /r/nowhere"
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

    test "a gh that can't be read is logged and nothing is closed or relanded", %{thread: t} do
      run = fn cmd, args, _opts ->
        send(self(), {:ran, [cmd | args]})
        {"gh: HTTP 502", 1}
      end

      log = ExUnit.CaptureLog.capture_log(fn -> KeepUp.red_checks("/repo", run) end)

      assert log =~ "red PRs unread" and log =~ "HTTP 502"
      refute_received {:ran, ["gh", "pr", "close" | _]}
      assert %Server.Thread{stage: "merged"} = Repo.get!(Server.Thread, t.id)
    end

    test "a gh that keeps failing the same way is said once, as one note, and the note clears once it reads" do
      failing = fn _cmd, _args, _opts -> {"gh: Could not resolve to a Repository", 1} end
      first = ExUnit.CaptureLog.capture_log(fn -> KeepUp.red_checks("/gone", failing) end)
      _ = :sys.get_state(Rollout)
      again = ExUnit.CaptureLog.capture_log(fn -> KeepUp.red_checks("/gone", failing) end)

      assert first =~ "red PRs unread"
      refute again =~ "unread"
      assert [%{text: "keep_up can't read red PRs of /gone" <> _}] = Rollout.pending()

      _ = KeepUp.red_checks("/gone", fn _cmd, _args, _opts -> {"[]", 0} end)
      _ = :sys.get_state(Rollout)
      assert Rollout.pending() == []
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

  # the git origin url (nil: no origin) and what `gh pr list` says, for every call of a pass
  defp pass(remote, gh_error) do
    fn
      "git", ["-C", _, "remote", "get-url", "origin"], _ ->
        if remote, do: {remote <> "\n", 0}, else: {"error: No such remote 'origin'\n", 2}

      "git", ["-C", _, "symbolic-ref" | _], _ ->
        {"feature\n", 0}

      "gh", ["pr", "list" | _], _ ->
        {gh_error, 1}

      _, _, _ ->
        {"", 0}
    end
  end

  describe "a repo with no GitHub to read" do
    test "a repo with no remote is skipped: no gh read, no rollout item" do
      KeepUp.keep_up("/r/no-remote", pass(nil, "no git remotes found"))

      assert notes("/r/no-remote") == []
    end

    test "a repo whose origin is not GitHub is skipped: no gh read, no rollout item" do
      for remote <- ["git@gitlab.com:acme/app.git", "https://gitlab.com/acme/app.git", "/srv/git/app.git"] do
        KeepUp.keep_up("/r/elsewhere", pass(remote, "none of the git remotes point to a known GitHub host"))
      end

      assert notes("/r/elsewhere") == []
    end

    test "a remote-less repo is said once across passes, not every pass" do
      first = ExUnit.CaptureLog.capture_log(fn -> KeepUp.keep_up("/r/quiet", pass(nil, "x")) end)
      again = ExUnit.CaptureLog.capture_log(fn -> KeepUp.keep_up("/r/quiet", pass(nil, "x")) end)

      assert first =~ "/r/quiet has no GitHub remote"
      refute again =~ "/r/quiet"
    end

    test "a repo GitHub can't resolve is one rollout item, not one per read" do
      remote = "https://github.com/launchscout/a11y-with-phoenix-guide.git"
      gh_error = "GraphQL: Could not resolve to a Repository with the name 'launchscout/a11y-with-phoenix-guide'"

      KeepUp.keep_up("/r/unresolvable", pass(remote, gh_error))
      KeepUp.keep_up("/r/unresolvable", pass(remote, gh_error))

      assert [_one] = notes("/r/unresolvable")
    end

    test "a failed read is not cleared by the other read succeeding" do
      run = fn
        "git", ["-C", _, "remote", "get-url", "origin"], _ ->
          {"https://github.com/acme/app.git\n", 0}

        "git", ["-C", _, "symbolic-ref" | _], _ ->
          {"feature\n", 0}

        "gh", ["pr", "list" | _] = args, _ ->
          if Enum.any?(args, &(&1 =~ "mergeStateStatus")), do: {"gh: HTTP 502", 1}, else: {"[]", 0}

        _, _, _ ->
          {"", 0}
      end

      KeepUp.keep_up("/r/half", run)

      assert [_one] = notes("/r/half")
    end
  end
end
