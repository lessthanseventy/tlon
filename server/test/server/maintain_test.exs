defmodule Server.MaintainTest do
  # Worklines slice 6: the Maintain back-edge. Deterministic sweeps detect control-band
  # breaches and act with NO human in the invocation path — but everything they open lands
  # GATED (machine-born), so the loop closes without ever acting unsupervised. One-brain E/2:
  # the sweeps are an Oban job (`Server.Jobs.Maintain`), performed by hand here.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Jobs.Maintain
  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline
  alias Server.Workline.Artifacts

  defmodule AllPresent do
    @moduledoc false
    @behaviour Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "present"}
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end

  # Bands at zero so anything open is stale now; `renag_ms` a day so a second sweep is quiet.
  defp sweep(args \\ %{}), do: perform_job(Maintain, Map.merge(%{gate_stale_ms: 0, renag_ms: to_timeout(day: 1)}, args))

  test "flag opens a machine-born workline already parked at the intent gate, evidence first" do
    {:ok, flagged} = Workline.flag(%{title: "maintain: x stalled", slug: "maint-x"}, "breach: no advance in 3d")

    assert flagged.born == "machine"
    assert flagged.stage == "intent"
    assert flagged.awaiting == "andrew"
    bodies = Message |> Repo.all() |> Enum.filter(&(&1.thread_id == flagged.id)) |> Enum.map(& &1.body)
    assert Enum.any?(bodies, &(&1 =~ "breach"))
  end

  defmodule NonePresent do
    @moduledoc false
    @behaviour Artifacts

    @impl true
    def check(_thread, requirement), do: {:error, "missing #{inspect(requirement)}"}
  end

  test "approve re-verifies the owed artifact — a vanished artifact keeps the gate parked" do
    thread = open_parked_gate("reverify")

    assert {:error, {:artifact_missing, _}} = Workline.approve(thread, artifacts: NonePresent)
    assert Repo.get!(Thread, thread.id).awaiting == "andrew"

    assert {:ok, approved} = Workline.approve(thread, artifacts: AllPresent)
    assert approved.stage == "plan"
  end

  test "approving a machine-born intent materializes intent.md from the evidence — one verb, chain intact" do
    tmp = Path.join(System.tmp_dir!(), "workline-flag-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    {_, 0} = System.cmd("git", ["-C", tmp, "init", "-q"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.email", "t@t"], stderr_to_stdout: true)
    {_, 0} = System.cmd("git", ["-C", tmp, "config", "user.name", "t"], stderr_to_stdout: true)
    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, tmp)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(tmp)
    end)

    {:ok, flagged} = Workline.flag(%{title: "no artifact", slug: "maint-bare"}, "breach evidence text")

    assert {:ok, approved} = Workline.approve(flagged)
    assert approved.stage == "spec"
    assert File.read!(Path.join(tmp, "work/maint-bare/intent.md")) =~ "breach evidence text"
  end

  test "a stale parked gate gets a reminder post, once per nag interval" do
    thread = open_parked_gate("stale-gate")

    assert :ok = sweep()
    assert :ok = sweep()

    reminders =
      Message |> Repo.all() |> Enum.filter(&(&1.thread_id == thread.id and &1.body =~ "still parked"))

    assert length(reminders) == 1
  end

  test "only a workline at its gate is nagged — not a plain thread waiting on a reply" do
    {:ok, plain} = Server.Channel.open_thread(%{title: "a question"})
    {:ok, _} = plain |> Ecto.Changeset.change(awaiting: "andrew") |> Repo.update()

    assert :ok = sweep()
    refute Enum.any?(Repo.all(Message), &(&1.thread_id == plain.id and &1.body =~ "still parked"))
  end

  test "a workline parked off its gate is waiting on a reply: the reminder says so, not approve" do
    {:ok, built} = Workline.open(%{title: "on hold", slug: "on-hold", stage: "build"})
    {:ok, _} = built |> Ecto.Changeset.change(awaiting: "andrew") |> Repo.update()

    assert :ok = sweep()

    assert [%Message{body: body}] =
             Message |> Repo.all() |> Enum.filter(&(&1.thread_id == built.id and &1.body =~ "still parked"))

    assert body =~ "waits on your reply"
    refute body =~ "approve"
  end

  test "a stalled workline opens no second workline: the needs list carries it as stalled" do
    {:ok, stalled} = Workline.open(%{title: "going nowhere", slug: "stuck"})

    assert :ok = sweep()
    assert :ok = sweep()

    assert Thread |> Repo.all() |> Enum.filter(&String.starts_with?(&1.slug || "", "maint-")) == []
    assert Repo.get!(Thread, stalled.id).awaiting == nil
  end

  test "a merged workline never breaches" do
    thread = walk_to_merged("done-line")

    assert :ok = sweep()

    assert Thread |> Repo.all() |> Enum.filter(&(&1.slug == "maint-done-line")) == []
    assert Repo.get!(Thread, thread.id).stage == "merged"
  end

  test "the default bands leave a fresh workline alone" do
    {:ok, _} = Workline.open(%{title: "just opened", slug: "fresh"})

    assert :ok = perform_job(Maintain, %{})

    assert Thread |> Repo.all() |> Enum.filter(&(&1.slug == "maint-fresh")) == []
  end

  test "the sweeps are on the half-hour cron" do
    plugins = Application.fetch_env!(:server, Oban)[:plugins]
    {_, cron} = Enum.find(plugins, &match?({Oban.Plugins.Cron, _}, &1))
    assert {"*/30 * * * *", Maintain} in cron[:crontab]
  end

  defp open_parked_gate(slug) do
    {:ok, thread} = Workline.open(%{title: slug, slug: slug})
    {:ok, thread} = Workline.advance(thread, artifacts: AllPresent)
    {:awaiting, parked} = Workline.advance(thread, artifacts: AllPresent)
    parked
  end

  defp walk_to_merged(slug) do
    {:ok, t} = Workline.open(%{title: slug, slug: slug})
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:awaiting, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.approve(t, artifacts: AllPresent)
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.advance(t, artifacts: AllPresent)
    {:awaiting, t} = Workline.advance(t, artifacts: AllPresent)
    {:ok, t} = Workline.approve(t, artifacts: AllPresent)
    t
  end

  test "a workline gone quiet is not nudged while the office is paused, and is once it is back to work" do
    path = Path.join(System.tmp_dir!(), "maintain-pause-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      File.rm(path)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    {:ok, w} = Workline.open(%{title: "quiet", slug: "quiet-#{System.unique_integer([:positive])}", stage: "plan"})
    nudged? = fn -> Enum.any?(Repo.all(Message), &(&1.thread_id == w.id and &1.body =~ "↻ continue")) end

    {:ok, _} = Server.Pause.pencils_down()
    sweep(%{quiet_ms: 0})
    refute nudged?.()

    {:ok, :working} = Server.Pause.back_to_work()
    sweep(%{quiet_ms: 0})
    assert nudged?.()
  end

  test "a workline gone quiet gets a nudge — a lead whose window died never goes idle to get one" do
    {:ok, w} = Workline.open(%{title: "quiet", slug: "quiet-#{System.unique_integer([:positive])}", stage: "plan"})
    sweep(%{quiet_ms: 0})
    assert Enum.any?(Repo.all(Message), &(&1.thread_id == w.id and &1.body =~ "↻ continue"))
  end

  test "the quiet band is the operator's quiet_workline_minutes knob" do
    path = Path.join(Path.expand("tmp"), "maintain-quiet-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)
    on_exit(fn -> Application.put_env(:server, :operator_config_path, prior) end)

    {:ok, w} = Workline.open(%{title: "quiet", slug: "quiet-#{System.unique_integer([:positive])}", stage: "plan"})
    two_hours_ago = DateTime.utc_now() |> DateTime.add(-7_200, :second) |> DateTime.truncate(:second)
    Repo.update_all(from(m in Message, where: m.thread_id == ^w.id), set: [created_at: two_hours_ago])
    nudged? = fn -> Enum.any?(Repo.all(Message), &(&1.thread_id == w.id and &1.body =~ "↻ continue")) end

    File.write!(path, ~s({"quiet_workline_minutes": 180}))
    sweep()
    refute nudged?.()

    File.write!(path, ~s({"quiet_workline_minutes": 60}))
    sweep()
    assert nudged?.()
  end

  describe "the board says what is true" do
    test "a ticket left doing with nothing open working on it goes back to the backlog, saying why" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Board"})
      {:ok, idle} = Server.Tickets.file(%{workspace_id: ws.id, title: "owned by nobody"})
      {:ok, _} = Server.Tickets.update(idle, %{status: "doing"})
      {:ok, busy} = Server.Tickets.file(%{workspace_id: ws.id, title: "being worked"})
      {:ok, th} = Server.Channel.open_thread(%{title: "work", workspace_id: ws.id})
      {:ok, _} = Server.Tickets.promote(busy, th.id)

      sweep()

      idle = Repo.get!(Server.Ticket, idle.id)
      assert idle.status == "backlog" and idle.body =~ "no open thread"
      assert Repo.get!(Server.Ticket, busy.id).status == "doing"
    end

    test "a ticket claimed by hand stays doing with no thread: someone is working it outside the office" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Claimed"})
      {:ok, t} = Server.Tickets.file(%{workspace_id: ws.id, title: "uqbar has it"})
      {:ok, _} = Server.Tickets.claim(t, "uqbar")

      sweep()

      assert %{status: "doing", assignee: "uqbar"} = Repo.get!(Server.Ticket, t.id)
    end

    test "a ticket started on an open thread but still in the backlog is doing" do
      {:ok, ws} = Server.Workspaces.register(%{name: "Board2"})
      {:ok, tk} = Server.Tickets.file(%{workspace_id: ws.id, title: "started"})
      {:ok, th} = Server.Channel.open_thread(%{title: "work", workspace_id: ws.id})
      {:ok, _} = Server.Tickets.tie(tk, th.id, "promoted")

      sweep()
      assert Repo.get!(Server.Ticket, tk.id).status == "doing"
    end
  end

  describe "worktrees no thread is working in" do
    setup do
      repo = Path.join(System.tmp_dir!(), "stale-wt-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(repo)

      git = fn args ->
        System.cmd("git", ["-C", repo, "-c", "user.email=t@t", "-c", "user.name=t" | args], stderr_to_stdout: true)
      end

      {_, 0} = git.(["init", "-q", "-b", "main"])
      File.write!(Path.join(repo, "a.txt"), "a\n")
      {_, 0} = git.(["add", "a.txt"])
      {_, 0} = git.(["commit", "-qm", "seed"])
      on_exit(fn -> File.rm_rf!(repo) end)

      {:ok, ws} = Server.Workspaces.register(%{name: "Trees"})

      {:ok, project} =
        Server.Projects.register(%{workspace_id: ws.id, name: "trees", repos: [%{"name" => "r", "path" => repo}]})

      %{repo: repo, git: git, ws: ws, project: project}
    end

    defp thread_with_tree(ctx, title) do
      {:ok, th} = Server.Channel.open_thread(%{title: title, workspace_id: ctx.ws.id, project_id: ctx.project.id})
      {:ok, wt} = Server.worktree_for_thread(th)
      {th, wt}
    end

    test "a closed thread's clean, merged worktree is removed; one holding work stays and is on the needs list", ctx do
      {done, done_wt} = thread_with_tree(ctx, "finished")
      {held, held_wt} = thread_with_tree(ctx, "abandoned")
      File.write!(Path.join(held_wt, "b.txt"), "work\n")
      {_, 0} = System.cmd("git", ["-C", held_wt, "add", "b.txt"])

      {_, 0} =
        System.cmd("git", ["-C", held_wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "unmerged work"])

      {:ok, _} = Server.Channel.close_thread(done)
      # close_thread now tracks a plain thread holding work; strand it the other way (closed row, work left behind)
      {:ok, _} = held |> Server.Thread.state_changeset("closed") |> Server.Repo.update()

      sweep()

      refute File.exists?(done_wt)
      assert File.exists?(held_wt)

      assert [%{kind: "stranded", level: "decide", text: text}] =
               Enum.filter(Server.Office.Needs.list(), &(&1.kind == "stranded"))

      assert text =~ Path.basename(held_wt) and text =~ "unmerged"
    end

    test "a workline that just landed is not stranded while GitHub merges it; an hour on, it is", ctx do
      {th, wt} = thread_with_tree(ctx, "just landed")
      File.write!(Path.join(wt, "b.txt"), "landing\n")
      {_, 0} = System.cmd("git", ["-C", wt, "add", "b.txt"])
      {_, 0} = System.cmd("git", ["-C", wt, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "landing"])
      {:ok, th} = th |> Server.Thread.workline_stage_changeset(%{stage: "merged"}) |> Server.Repo.update()
      {:ok, _} = Server.Channel.close_thread(th)

      {:ok, landed} =
        Server.Dossier.record_event(%{
          thread_id: th.id,
          kind: "stage_advanced",
          correlation: "workline:t",
          detail: %{"from" => "review", "to" => "merged"}
        })

      assert Enum.filter(Server.Office.Needs.list(), &(&1.kind == "stranded")) == []

      landed |> Ecto.Changeset.change(created_at: DateTime.add(landed.created_at, -2, :hour)) |> Server.Repo.update!()
      assert [%{kind: "stranded"}] = Enum.filter(Server.Office.Needs.list(), &(&1.kind == "stranded"))
    end

    test "an open thread's worktree is left alone", ctx do
      {_th, wt} = thread_with_tree(ctx, "in progress")
      sweep()
      assert File.exists?(wt)
      assert Enum.filter(Server.Office.Needs.list(), &(&1.kind == "stranded")) == []
    end
  end
end
