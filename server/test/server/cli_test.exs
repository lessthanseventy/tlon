defmodule Server.CLITest do
  # `Server.CLI` — the verbs `scripts/tlon-cli.sh` runs in the live node: each answers the exact
  # line the shell prints, `{:error, _}` where the shell exits non-zero.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Server.{Channel, CLI, Dossier, Repo, Thread, Tickets, Workline, Workspaces}

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Workspaces.register(%{name: "Cli"})
    {:ok, ws: ws}
  end

  defp ticket(ws, attrs \\ %{}), do: elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: "a ticket"}, attrs)), 1)
  defp thread(ws), do: elem(Channel.open_thread(%{title: "a thread", workspace_id: ws.id}), 1)

  describe "out/2" do
    test "an ok prints its text; an error prints it on the chosen device and raises" do
      assert capture_io(fn -> CLI.out({:ok, "done"}) end) == "done\n"
      assert capture_io(fn -> assert_raise RuntimeError, "refused", fn -> CLI.out({:error, "no"}) end end) == "no\n"

      assert capture_io(:stderr, fn ->
               assert_raise RuntimeError, fn -> CLI.out({:error, "no"}, :stderr) end
             end) == "no\n"
    end
  end

  describe "tickets" do
    test "ticket_file files, and refuses a ticket with no title", %{ws: ws} do
      assert {:ok, "filed ticket #" <> rest} = CLI.ticket_file(ws.id, nil, "fix it", "the body")
      assert rest =~ " — fix it"
      assert {:error, "refused: [title:" <> _} = CLI.ticket_file(ws.id, nil, "", "")
    end

    test "epic_new files an epic and epic_add ties tickets to it, all or nothing", %{ws: ws} do
      assert {:ok, "filed epic #" <> _} = CLI.epic_new(ws.id, "the epic", "design")
      assert {:error, "refused: [title:" <> _} = CLI.epic_new(ws.id, "", "")

      epic = ticket(ws, %{kind: "epic", title: "e"})
      [a, b] = [ticket(ws), ticket(ws)]
      assert CLI.epic_add(epic.id, [a.id, b.id]) == {:ok, "epic ##{epic.id} now holds 2 ticket(s)"}
      assert {:error, "refused #" <> _} = CLI.epic_add(epic.id, [a.id, 0])
    end

    test "ticket_route, ticket_start and ticket_claim say no ticket, and refuse an epic", %{ws: ws} do
      epic = ticket(ws, %{kind: "epic", title: "e"})

      for call <- [&CLI.ticket_route/1, &CLI.ticket_start/1, &CLI.ticket_delete/1] do
        assert call.(0) == {:error, "no ticket #0"}
      end

      assert CLI.ticket_claim(0, "uqbar") == {:error, "no ticket #0"}
      assert CLI.ticket_route(epic.id) == {:error, "refused: :epic"}
      assert CLI.ticket_start(epic.id) == {:error, "refused: :epic"}
      assert CLI.ticket_claim(epic.id, "uqbar") == {:error, "refused: :epic"}
    end

    test "ticket_claim claims for the named handle", %{ws: ws} do
      t = ticket(ws)
      assert CLI.ticket_claim(t.id, "uqbar") == {:ok, "ticket ##{t.id} claimed by uqbar"}
      assert Tickets.get(t.id).status == "doing"
    end

    test "ticket_start refuses until the root machine thread exists, then ticket_route starts it", %{ws: ws} do
      t = ticket(ws)
      assert CLI.ticket_start(t.id) == {:error, "refused: :root_machine_thread"}
      assert {:ok, "no manager: ticket #" <> rest} = CLI.ticket_route(t.id)
      assert rest =~ "started as thread #"
      assert {:ok, "started ticket #" <> _} = CLI.ticket_start(ticket(ws).id)
    end

    test "ticket_set changes one field, and refuses a bad value", %{ws: ws} do
      t = ticket(ws)
      assert CLI.ticket_set(t.id, "title", "renamed") == {:ok, "ticket ##{t.id} title set"}
      assert Tickets.get(t.id).title == "renamed"
      assert {:error, "refused: [status:" <> _} = CLI.ticket_set(t.id, "status", "nonsense")
      assert CLI.ticket_set(0, "title", "x") == {:error, "no ticket #0"}
    end

    test "ticket_delete removes it", %{ws: ws} do
      t = ticket(ws)
      assert CLI.ticket_delete(t.id) == {:ok, "deleted ticket ##{t.id}"}
      assert Tickets.get(t.id) == nil
    end
  end

  describe "the dossier" do
    test "forget_fact tombstones a fact; an unknown id is said, not raised" do
      {:ok, fact} = Dossier.bank_fact(%{kind: "learned", text: "a thing", provenance: "derived"})
      assert CLI.forget_fact(fact.id) == {:ok, "forgot fact ##{fact.id} — a thing"}
      assert Repo.get(Server.Fact, fact.id).forgotten_at
      assert CLI.forget_fact(0) == {:ok, "no fact #0"}
    end

    test "resolve_issue closes an issue with or without a resolution", %{ws: ws} do
      t = thread(ws)
      {:ok, issue} = Dossier.raise_issue(%{thread_id: t.id, summary: "it broke", kind: "bug"})
      assert CLI.resolve_issue(issue.id, "fixed in 1") == {:ok, "resolved issue ##{issue.id} — it broke"}
      assert Repo.get(Server.Issue, issue.id).state == "closed"
      assert CLI.resolve_issue(0) == {:ok, "no issue #0"}
    end

    test "record_verify records a check correlated to the workline's verify", %{ws: ws} do
      t = thread(ws)
      assert {:ok, "recorded #" <> rest} = CLI.record_verify(t.id, "a-slug", 0, "mix test", "ok")
      assert rest =~ "check"
    end
  end

  describe "posting" do
    test "post speaks as the operator, note as tlon", %{ws: ws} do
      t = thread(ws)
      op = Server.OperatorConfig.operator()
      assert {:ok, "posted #" <> posted} = CLI.post(t.id, "hello")
      assert posted =~ "to thread ##{t.id} as #{op}"
      assert {:ok, noted} = CLI.note(t.id, "a report")
      assert noted =~ "to thread ##{t.id} as tlon"
    end

    test "post_as posts as a citizen, and refuses a seated coworker's name", %{ws: ws} do
      t = thread(ws)
      {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
      assert {:ok, posted} = CLI.post_as(t.id, "uqbar", "a margin note", true)
      assert posted =~ "to thread ##{t.id} as uqbar"
      {:ok, _} = Workspaces.register(%{name: "Seated", roster: [%{"archetype" => "planner", "name" => "yu"}]})
      assert {:error, "refused: " <> _} = CLI.post_as(t.id, "yu", "impersonating", false)
    end

    test "answer refuses a prompt that is not there" do
      assert {:error, "refused: " <> _} = CLI.answer(0, "1")
    end
  end

  describe "threads" do
    test "close_thread closes a plain thread, and refuses an unknown one", %{ws: ws} do
      t = thread(ws)
      assert CLI.close_thread(t.id, nil, "") == {:ok, "closed thread ##{t.id} — a thread"}
      assert CLI.close_thread(0, nil, "") == {:error, "no thread #0"}
    end

    test "close_thread asks an unmerged workline for a why, and takes one" do
      {:ok, w} = Workline.open(%{title: "w", slug: "cli-close"})
      assert {:error, "refused: #" <> rest} = CLI.close_thread(w.id, nil, "")
      assert rest =~ "close-thread #{w.id} superseded <pr-or-commit> | resolved <why> | abandoned <why>"
      assert CLI.close_thread(w.id, "abandoned", "not wanted") == {:ok, "closed thread ##{w.id} — w"}
    end

    test "reopen opens a closed thread again", %{ws: ws} do
      t = thread(ws)
      {:ok, _} = Channel.close_as(t, nil)
      assert CLI.reopen(t.id) == {:ok, "reopened thread ##{t.id} — a thread"}
      assert CLI.reopen(0) == {:error, "no thread #0"}
    end

    test "delete_thread deletes it; an unknown id is said", %{ws: ws} do
      t = thread(ws)
      assert CLI.delete_thread(t.id) == {:ok, "deleted thread ##{t.id} — a thread"}
      assert Repo.get(Thread, t.id) == nil
      assert CLI.delete_thread(t.id) == {:ok, "no thread ##{t.id}"}
    end

    test "hand_off refuses a handle nobody holds", %{ws: ws} do
      t = thread(ws)
      assert {:error, "refused: " <> _} = CLI.hand_off(t.id, "nobody")
    end
  end

  describe "worklines" do
    test "workline opens one at intent, and refuses a slug twice" do
      assert {:ok, opened} = CLI.workline("a title", "cli-open")
      assert opened =~ " cli-open at intent — folder work/cli-open/"
      assert {:ok, "refused: " <> _} = CLI.workline("again", "cli-open")
    end

    test "track promotes a plain thread; an unknown id is said", %{ws: ws} do
      t = thread(ws)
      assert {:ok, tracked} = CLI.track(t.id)
      assert tracked =~ "tracked — thread ##{t.id} is workline"
      assert CLI.track(0) == {:ok, "no thread #0"}
    end

    test "advance says where a workline is when it is not at the from-stage" do
      {:ok, w} = Workline.open(%{title: "w", slug: "cli-adv"})
      assert CLI.advance(w.id, "build") == {:ok, "not advanced — thread ##{w.id} is at intent now, not build"}
      assert CLI.advance(0, "") == {:ok, "no thread #0"}
      assert {:ok, "refused: " <> _} = CLI.advance(w.id, "")
    end

    test "approve says no thread, and refuses a gate that is not parked" do
      {:ok, w} = Workline.open(%{title: "w", slug: "cli-approve"})
      assert CLI.approve(0, []) == {:ok, "no thread #0"}
      assert {:ok, "refused: " <> _} = CLI.approve(w.id, [])
    end

    test "send_back and red_verify say no thread, and refuse a thread that is not a workline", %{ws: ws} do
      t = thread(ws)
      assert CLI.send_back(0, "plan", "why", false) == {:error, "no thread #0"}
      assert {:error, "refused: " <> _} = CLI.send_back(t.id, "plan", "why", false)
      assert CLI.red_verify(0, "red") == {:error, "no thread #0"}
      assert {:ok, "left as is: " <> _} = CLI.red_verify(t.id, "red")
    end

    test "send_back moves a workline back to build" do
      {:ok, w} = Workline.open(%{title: "w", slug: "cli-back", stage: "verify"})
      assert {:ok, "sent back — thread #" <> rest} = CLI.send_back(w.id, "build", "a nit", false)
      assert rest =~ "now at build, led by "
    end
  end

  describe "the merge line" do
    test "branch_review is null when nothing reviewed the branch" do
      assert CLI.branch_review("no-such-branch") == {:ok, "null"}
    end

    test "land_pr refuses a branch no review approves" do
      assert {:error, "refused: " <> _} = CLI.land_pr(1, "no-such-branch", "")
    end
  end

  describe "settings" do
    test "flag turns a flag on and off, and says an unknown one" do
      assert CLI.flag("build_mode", true) == {:ok, "build_mode is now on"}
      assert CLI.flag("build_mode", false) == {:ok, "build_mode is now off"}
      assert {:ok, "no flag named nope" <> _} = CLI.flag("nope", true)
    end

    test "pause names the office's state" do
      path = Path.join(System.tmp_dir!(), "cli-pause-#{System.pid()}-#{System.unique_integer([:positive])}.json")
      prior = Application.get_env(:server, :operator_config_path)
      Application.put_env(:server, :operator_config_path, path)
      File.write!(path, "{}")

      on_exit(fn ->
        File.rm(path)

        if prior,
          do: Application.put_env(:server, :operator_config_path, prior),
          else: Application.delete_env(:server, :operator_config_path)
      end)

      assert CLI.pause("pencils_down") == {:ok, "the office: pencils_down"}
      assert CLI.pause("back_to_work") == {:ok, "the office: working"}
    end
  end
end
