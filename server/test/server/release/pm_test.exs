defmodule Server.Release.PMTest do
  # The PM's release desk (pm-and-release design §4, §6): status, a proposal graded commit by commit,
  # the cut under the standing approval or one gate for the operator, and the changelog. Real git in a
  # throwaway repo; the release script, the grader and the restart are stubs.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Attention
  alias Server.Channel
  alias Server.Release.PM
  alias Server.Repo
  alias Server.ScheduleRun

  @low %{"scope" => 1, "reversibility" => 1, "blast" => 1, "detectability" => 1, "proof" => 1}

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Machine"})

    dir = Path.join(System.tmp_dir!(), "pm-test-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    repo = Path.join(dir, "tlon")
    File.mkdir_p!(repo)
    now = System.os_time(:second)

    git!(repo, ["init", "-q"])
    git!(repo, ["config", "user.email", "t@t"])
    git!(repo, ["config", "user.name", "t"])
    commit!(repo, "README", "seed\n", "seed", now - 7200)
    git!(repo, ["branch", "live"])
    commit!(repo, "lamp.txt", "the lamp says hello\n", "office: the lamp says hello", now + 60)
    commit!(repo, "desk.txt", "the desk says hello\n", "office: the desk says hello", now + 120)
    git!(repo, ["update-ref", "refs/remotes/origin/main", "HEAD"])

    # the release script: records its arguments, moves live as the real one does
    script = Path.join(dir, "release.sh")
    File.write!(script, "#!/bin/sh\necho \"$@\" >> #{dir}/cut.log\ngit -C #{repo} branch -f live \"$2\"\necho cut\n")
    File.chmod!(script, 0o755)

    {:ok, sched} =
      Server.Schedules.create(%{workspace_id: ws.id, kind: "script", title: "nightly", body: "true", cron: "@daily"})

    me = self()

    opts = [
      root: repo,
      script: script,
      busy: fn -> [] end,
      restart: fn why -> send(me, {:restart, why}) end,
      hot_load: fn _from, _to -> {:restart, "a process module changed: X"} end,
      auto_land_risk: 2
    ]

    %{ws: ws, repo: repo, dir: dir, sched: sched, opts: opts, main: rev(repo, "HEAD"), live: rev(repo, "live")}
  end

  defp git!(repo, args, env \\ []) do
    {out, 0} = System.cmd("git", ["-C", repo | args], env: env, stderr_to_stdout: true)
    out
  end

  defp commit!(repo, file, text, subject, at) do
    File.mkdir_p!(Path.dirname(Path.join(repo, file)))
    File.write!(Path.join(repo, file), text)
    git!(repo, ["add", file])
    date = "@#{at} +0000"
    git!(repo, ["commit", "-qm", subject], [{"GIT_COMMITTER_DATE", date}, {"GIT_AUTHOR_DATE", date}])
  end

  defp rev(repo, ref), do: repo |> git!(["rev-parse", ref]) |> String.trim()

  defp checks_pass!(%{sched: s}, sha) do
    now = DateTime.truncate(DateTime.utc_now(), :second)

    for check <- ~w(gate smoke),
        do:
          Repo.insert!(%ScheduleRun{
            schedule_id: s.id,
            status: "ok",
            check_name: check,
            sha: sha,
            started_at: now,
            finished_at: now
          })
  end

  # the grader answers every commit with `scores`, each reason quoting "says hello"
  defp grader!(%{dir: dir}, scores) do
    reasons = Map.new(Server.Workline.Grade.axes(), &{&1, %{"why" => "ok", "kind" => "fact", "quote" => "says hello"}})
    answer = Jason.encode!(%{"scores" => scores, "reasons" => reasons, "decisions" => [], "fixes" => []})
    cli = Path.join(dir, "grader")
    File.write!(cli, "#!/bin/sh\necho asked >> #{dir}/grader.log\ncat <<'EOF'\n#{answer}\nEOF\n")
    File.chmod!(cli, 0o755)
    Application.put_env(:server, :grader_cmd, cli)
    on_exit(fn -> Application.delete_env(:server, :grader_cmd) end)
  end

  defp root(ws), do: Channel.machine_thread(ws.id)
  defp cuts(%{dir: dir}), do: File.read(Path.join(dir, "cut.log"))
  defp bodies(ws), do: ws |> root() |> Channel.thread_messages() |> Enum.map(& &1.body)

  defp gate(ws) do
    Repo.one(
      from m in Server.Message,
        where: m.thread_id == ^root(ws).id and m.kind == "prompt" and is_nil(m.resolved_at)
    )
  end

  test "status: what runs, what main has that it doesn't, and main's checks", ctx do
    checks_pass!(ctx, ctx.main)
    assert {:ok, s} = PM.status(ctx.opts)
    assert s.live == ctx.live and s.main == ctx.main
    assert Enum.map(s.waiting, & &1.subject) == ["office: the lamp says hello", "office: the desk says hello"]
    assert List.last(s.checks) == "releasable: yes"
  end

  describe "check/2" do
    setup ctx do
      me = self()
      %{opts: Keyword.put(ctx.opts, :run, &send(me, {:fired, &1.body}))}
    end

    test "fires the gate and the smoke on main's tip, making each its nightly schedule if it has none", ctx do
      assert {:ok, results} = PM.check(ctx.ws.id, ctx.opts)
      assert Enum.map(results, &{&1.check, &1.state}) == [{"gate", "started"}, {"smoke", "started"}]
      assert_received {:fired, "mise run check:main"}
      assert_received {:fired, "mise run release:smoke"}

      bodies = for s <- Server.Schedules.in_workspace(ctx.ws.id), s.kind == "script", do: {s.body, s.standing, s.dir}
      assert {"mise run check:main", true, ctx.repo} in bodies
      assert {"mise run release:smoke", true, ctx.repo} in bodies

      assert {:ok, _} = PM.check(ctx.ws.id, ctx.opts)
      assert length(Server.Schedules.in_workspace(ctx.ws.id)) == 3
    end

    test "a check that already passed on main's tip, or is running now, is not fired again", ctx do
      checks_pass!(ctx, ctx.main)
      Repo.delete_all(from r in ScheduleRun, where: r.check_name == "smoke")

      {:ok, smoke} =
        Server.Schedules.create(%{
          workspace_id: ctx.ws.id,
          kind: "script",
          title: "smoke",
          body: "mise run release:smoke",
          cron: "@daily"
        })

      Repo.insert!(%ScheduleRun{
        schedule_id: smoke.id,
        status: "running",
        started_at: DateTime.truncate(DateTime.utc_now(), :second)
      })

      assert {:ok, [gate, running]} = PM.check(ctx.ws.id, ctx.opts)
      assert {gate.check, gate.state} == {"gate", "passed"}
      assert {running.check, running.state} == {"smoke", "running"}
      refute_received {:fired, _}
    end
  end

  describe "propose/4" do
    test "refused unless releasable: the gate and the smoke on exactly that commit", ctx do
      assert {:error, why} = PM.propose(ctx.ws.id, nil, nil, ctx.opts)
      assert why =~ "not releasable" and why =~ "no check:main"
    end

    test "refused when nothing waits, or the commit isn't on main", ctx do
      checks_pass!(ctx, ctx.live)
      assert {:error, why} = PM.propose(ctx.ws.id, ctx.live, nil, ctx.opts)
      assert why =~ "nothing waits"

      git!(ctx.repo, ["checkout", "-qb", "side"])
      commit!(ctx.repo, "x.txt", "x\n", "side", System.os_time(:second))
      assert {:error, why} = PM.propose(ctx.ws.id, rev(ctx.repo, "side"), nil, ctx.opts)
      assert why =~ "not on origin/main"
    end

    test "releasable: queued to be graded off the request path", ctx do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      checks_pass!(ctx, ctx.main)

      assert {:ok, %{sha: sha, changes: 2}} = PM.propose(ctx.ws.id, nil, "the lamp and the desk talk", ctx.opts)
      assert sha == ctx.main
      assert_enqueued(worker: Server.Jobs.Release, args: %{action: "decide", sha: sha, workspace_id: ctx.ws.id})
    end
  end

  describe "decide/4" do
    test "every change fits the standing approval: it cuts, says so, posts the changelog, restarts", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, @low)

      assert {:ok, _} = PM.decide(ctx.ws.id, ctx.main, "The lamp and the desk say hello now.", ctx.opts)
      assert {:ok, log} = cuts(ctx)
      assert log == "cut #{ctx.main} --no-restart\n"
      assert_received {:restart, why}
      assert why =~ String.slice(ctx.main, 0, 7)

      [fits, changelog, _needs_a_restart] = Enum.take(bodies(ctx.ws), -3)
      assert fits =~ "fit your standing approval"
      assert changelog =~ "The lamp and the desk say hello now."
      assert changelog =~ "office: the desk says hello"

      assert %{detail: %{"changelog" => ^changelog, "from" => live}} =
               Repo.one(from e in Server.Event, where: e.correlation == ^"release:#{ctx.main}")

      assert live == ctx.live
    end

    test "a cut the script says needs no restart says it is live instead", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, @low)
      script = ctx.opts[:script]
      File.write!(script, File.read!(script) <> "echo 'restart: not needed'\n")

      assert {:ok, _} = PM.decide(ctx.ws.id, ctx.main, "Lamp talk.", ctx.opts)
      refute_received {:restart, _}
      assert List.last(bodies(ctx.ws)) =~ "release #{String.slice(ctx.main, 0, 7)} is live"
    end

    test "a commit subject that says the phrase doesn't skip the restart", ctx do
      commit!(ctx.repo, "lamp.txt", "again\n", "restart: not needed", System.os_time(:second) + 180)
      main = rev(ctx.repo, "HEAD")
      git!(ctx.repo, ["update-ref", "refs/remotes/origin/main", main])
      checks_pass!(ctx, main)
      grader!(ctx, @low)
      script = ctx.opts[:script]
      File.write!(script, File.read!(script) <> "echo '  abc1234 restart: not needed'\n")

      assert {:ok, _} = PM.decide(ctx.ws.id, main, "Lamp talk.", ctx.opts)
      assert_received {:restart, _}
    end

    test "a release that hot-loads needs no restart and is said live", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, @low)
      me = self()

      hot_load = fn from, to ->
        send(me, {:hot_load, from, to})
        {:ok, [Some.Module]}
      end

      assert {:ok, _} = PM.decide(ctx.ws.id, ctx.main, "Lamp talk.", Keyword.put(ctx.opts, :hot_load, hot_load))
      assert_received {:hot_load, from, to}
      assert {from, to} == {ctx.live, ctx.main}
      refute_received {:restart, _}

      body = Enum.join(bodies(ctx.ws), "\n")
      assert body =~ "loaded without a restart: 1 modules"
      assert List.last(bodies(ctx.ws)) =~ "release #{String.slice(ctx.main, 0, 7)} is live"
    end

    test "a release that can't hot-load says why and asks for the restart", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, @low)

      assert {:ok, _} = PM.decide(ctx.ws.id, ctx.main, "Lamp talk.", ctx.opts)
      assert_received {:restart, _}
      assert Enum.join(bodies(ctx.ws), "\n") =~ "needs a restart: a process module changed: X"
    end

    test "a restart the server refuses is said on the root thread", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, @low)
      opts = Keyword.put(ctx.opts, :restart, fn _why -> {:error, "not under systemd: run mise run server:restart"} end)

      assert {:ok, _} = PM.decide(ctx.ws.id, ctx.main, "Lamp talk.", opts)

      assert List.last(bodies(ctx.ws)) ==
               "release #{String.slice(ctx.main, 0, 7)} is cut, but its restart was refused: not under systemd: run mise run server:restart"
    end

    test "a change over the standing approval: one gate for the operator, nothing cut", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, %{@low | "blast" => 4})

      assert {:gate, _} = PM.decide(ctx.ws.id, ctx.main, "Lamp talk.", ctx.opts)
      assert {:error, :enoent} = cuts(ctx)
      refute_received {:restart, _}

      gate = gate(ctx.ws)
      assert gate.payload["release"] == ctx.main
      assert Enum.map(gate.payload["options"], & &1["label"]) == ["approve", "not yet"]
      assert gate.body =~ "Lamp talk." and gate.body =~ "blast 4" and gate.body =~ "releasable: yes"

      assert [%{kind: "gate", scope: "release", text: summary}] =
               Enum.filter(Server.Office.Needs.list(), &(&1.thread_id == root(ctx.ws).id))

      assert summary =~ "release #{String.slice(ctx.main, 0, 7)}: 2 changes"
    end

    test "a migration always waits, and the grader isn't asked about it", ctx do
      commit!(ctx.repo, "priv/repo/migrations/1_x.exs", "says hello\n", "a migration", System.os_time(:second) + 180)
      git!(ctx.repo, ["update-ref", "refs/remotes/origin/main", "HEAD"])
      main = rev(ctx.repo, "HEAD")
      checks_pass!(ctx, main)
      grader!(ctx, @low)

      assert {:gate, _} = PM.decide(ctx.ws.id, main, nil, ctx.opts)
      assert gate(ctx.ws).body =~ "a database migration"
      assert {:error, :enoent} = cuts(ctx)
    end

    test "with no standing approval set, every release waits for the operator, ungraded", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, @low)

      assert {:gate, _} = PM.decide(ctx.ws.id, ctx.main, nil, Keyword.put(ctx.opts, :auto_land_risk, nil))
      assert gate(ctx.ws).body =~ "no standing approval"
      assert {:error, :enoent} = File.read(Path.join(ctx.dir, "grader.log"))
    end

    test "a new proposal supersedes the open gate: one gate, never two", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, %{@low | "blast" => 4})

      {:gate, first} = PM.decide(ctx.ws.id, ctx.main, nil, ctx.opts)
      {:gate, second} = PM.decide(ctx.ws.id, ctx.main, nil, ctx.opts)
      assert gate(ctx.ws).id == second.id
      assert Repo.get(Server.Message, first.id).resolution == "superseded"
    end

    test "the gate is no pane's: the switchboard doesn't hold the root thread, the reconcile leaves it", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, %{@low | "blast" => 4})
      {:gate, gate} = PM.decide(ctx.ws.id, ctx.main, nil, ctx.opts)

      refute Attention.waiting?(root(ctx.ws).id)
      Attention.tick(ctx.ws.id)
      assert is_nil(Repo.get(Server.Message, gate.id).resolved_at)
    end
  end

  describe "answering the gate by its id (Attention.answer_prompt/3, the Needs answer path)" do
    setup ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, %{@low | "blast" => 4})
      {:gate, gate} = PM.decide(ctx.ws.id, ctx.main, "Lamp talk.", ctx.opts)
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      %{gate: gate}
    end

    test "approve: the gate resolves and the cut is queued", ctx do
      assert {:ok, reply} = Attention.answer_prompt(ctx.gate.id, "andrew", "a")
      assert reply.reply_to == ctx.gate.id
      assert Repo.get(Server.Message, ctx.gate.id).resolution == "answered: a"

      assert_enqueued(
        worker: Server.Jobs.Release,
        args: %{action: "cut", sha: ctx.main, workspace_id: ctx.ws.id, notes: "Lamp talk."}
      )
    end

    test "not yet: the gate resolves and nothing is queued", ctx do
      assert {:ok, _} = Attention.answer_prompt(ctx.gate.id, "andrew", "not yet")
      assert Repo.get(Server.Message, ctx.gate.id).resolution == "answered: not yet"
      refute_enqueued(worker: Server.Jobs.Release)
    end
  end

  describe "cut/4" do
    test "the changelog lists the worklines merged since live, then the commits", ctx do
      checks_pass!(ctx, ctx.main)
      in_window = workline_merged!(ctx.ws, "the lamp talks", DateTime.utc_now())
      _before = workline_merged!(ctx.ws, "an old one", DateTime.add(DateTime.utc_now(), -3, :hour))

      assert {:ok, changelog} = PM.cut(ctx.ws.id, ctx.main, "You can talk to the lamp.", ctx.opts)
      assert changelog =~ "You can talk to the lamp."
      assert changelog =~ "##{in_window.id} the lamp talks"
      refute changelog =~ "an old one"
      assert changelog =~ "office: the lamp says hello"
    end

    test "refused unless releasable at the moment of the cut", ctx do
      checks_pass!(ctx, ctx.main)
      busy = Keyword.put(ctx.opts, :busy, fn -> ["the verify of #7 is running"] end)

      assert {:error, why} = PM.cut(ctx.ws.id, ctx.main, nil, busy)
      assert why =~ "the verify of #7 is running"
      assert {:error, :enoent} = cuts(ctx)
      assert List.last(bodies(ctx.ws)) =~ "not cut"
    end

    test "a script that fails is said on the root thread, recorded as a failed cut, and nothing restarted", ctx do
      checks_pass!(ctx, ctx.main)
      File.write!(ctx.opts[:script], "#!/bin/sh\necho 'release: the build failed'\nexit 1\n")

      assert {:error, _} = PM.cut(ctx.ws.id, ctx.main, nil, ctx.opts)
      assert List.last(bodies(ctx.ws)) =~ "the build failed"
      refute_received {:restart, _}
      refute Repo.exists?(from e in Server.Event, where: like(e.correlation, "release:%") and e.kind == "check_passed")
    end

    test "a failed cut is a release_failed Need until a cut succeeds; retrying it queues the cut again", ctx do
      start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
      checks_pass!(ctx, ctx.main)
      script = File.read!(ctx.opts[:script])
      File.write!(ctx.opts[:script], "#!/bin/sh\necho 'release: the build failed'\nexit 1\n")
      assert {:error, _} = PM.cut(ctx.ws.id, ctx.main, "the lamp talks", ctx.opts)

      assert [need] = Enum.filter(Server.Office.Needs.list(), &(&1.kind == "release_failed"))
      assert need.thread_id == root(ctx.ws).id and need.text =~ "the build failed"

      assert [%{actions: [%{label: "Retry the cut", path: path} | _]}] =
               Server.Alerts.build([need], [], DateTime.utc_now())

      assert path == "/api/release/retry/#{need.ref}"

      assert {:ok, sha} = PM.retry(need.ref)
      assert sha == ctx.main
      assert_enqueued(worker: Server.Jobs.Release, args: %{action: "cut", sha: sha, notes: "the lamp talks"})

      File.write!(ctx.opts[:script], script)
      assert {:ok, _} = PM.cut(ctx.ws.id, ctx.main, "the lamp talks", ctx.opts)
      refute Enum.any?(Server.Office.Needs.list(), &(&1.kind == "release_failed"))
    end
  end

  test "the nightly cut is on the crontab, and the job runs it" do
    {_, cron} = Enum.find(Application.fetch_env!(:server, Oban)[:plugins], &match?({Oban.Plugins.Cron, _}, &1))
    assert {"0 11 * * *", Server.Jobs.Release, args: %{"action" => "auto"}} in cron[:crontab]

    Application.put_env(:server, :release_root, Path.join(System.tmp_dir!(), "no-such-repo-#{System.pid()}"))
    on_exit(fn -> Application.delete_env(:server, :release_root) end)
    assert :ok = perform_job(Server.Jobs.Release, %{"action" => "auto"})
  end

  describe "auto/1 (the nightly cut)" do
    setup ctx do
      grader!(ctx, @low)
      %{opts: Keyword.put(ctx.opts, :busy, fn -> ["a coworker mid-turn"] end)}
    end

    test "cuts the newest commit that passed both checks, however busy the office", ctx do
      older = rev(ctx.repo, "HEAD~1")
      checks_pass!(ctx, older)

      assert {:ok, _} = PM.auto(ctx.opts)
      assert {:ok, log} = cuts(ctx)
      assert log == "cut #{older} --no-restart\n"
      assert_received {:restart, _}
    end

    test "a commit past the standing approval gets the operator's one gate, and only once", ctx do
      checks_pass!(ctx, ctx.main)
      grader!(ctx, %{@low | "blast" => 4})

      assert {:gate, _} = PM.auto(ctx.opts)
      assert :asked = PM.auto(ctx.opts)
      assert {:error, :enoent} = cuts(ctx)
    end

    test "no commit passed both: says so and cuts nothing", ctx do
      assert :none = PM.auto(ctx.opts)
      assert List.last(bodies(ctx.ws)) =~ "2 changes waiting"
      assert {:error, :enoent} = cuts(ctx)
    end

    test "cuts nothing while the office is paused", ctx do
      checks_pass!(ctx, ctx.main)
      path = Path.join(ctx.dir, "settings.json")
      File.write!(path, ~s({"pause": "pencils_down"}))
      prior = Application.get_env(:server, :operator_config_path)
      Application.put_env(:server, :operator_config_path, path)
      on_exit(fn -> Application.put_env(:server, :operator_config_path, prior) end)

      assert {:error, _} = PM.auto(ctx.opts)
      assert {:error, :enoent} = cuts(ctx)
    end

    test "cuts nothing after a rollback, until the operator cuts forward", ctx do
      checks_pass!(ctx, ctx.main)
      git!(ctx.repo, ["branch", "-f", "live", ctx.main])
      :ok = PM.note_live(root: ctx.repo)
      git!(ctx.repo, ["branch", "-f", "live", ctx.live])
      :ok = PM.note_live(root: ctx.repo)

      assert true = PM.auto(ctx.opts)
      assert {:error, :enoent} = cuts(ctx)
    end

    test "cuts nothing while a restart waits: it may be a rollback's, not yet said live", ctx do
      checks_pass!(ctx, ctx.main)
      waiter = spawn_link(fn -> Process.sleep(:infinity) end)
      Process.register(waiter, :tlon_restart_waiter)

      assert true = PM.auto(ctx.opts)
      assert {:error, :enoent} = cuts(ctx)
    end
  end

  describe "note_live/1 (the service booting on what the pointer names)" do
    test "a server behind the pointer's code restarts instead of saying live; its boot says it", ctx do
      on_exit(fn -> :persistent_term.erase({PM, :booted}) end)
      assert :ok = PM.boot(root: ctx.repo)
      said = length(bodies(ctx.ws))
      restart = [root: ctx.repo, restart: fn why -> send(self(), {:restart, why}) end]
      now = System.os_time(:second)

      commit!(ctx.repo, "scripts/a.sh", "true\n", "scripts: a", now + 180)
      git!(ctx.repo, ["branch", "-f", "live", "HEAD"])
      assert :ok = PM.note_live(restart)
      refute_received {:restart, _}
      assert length(bodies(ctx.ws)) == said + 1

      for file <- ["server/lib/a.ex", "mise.toml"] do
        commit!(ctx.repo, file, "changed\n", "changes #{file}", now + 240)
        git!(ctx.repo, ["branch", "-f", "live", "HEAD"])
        assert :restarting = PM.note_live(restart)
        assert_received {:restart, _}
        assert length(bodies(ctx.ws)) == said + 1
      end

      commit!(ctx.repo, "scripts/b.sh", "true\n", "scripts: b, over the unbooted cut", now + 300)
      git!(ctx.repo, ["branch", "-f", "live", "HEAD"])
      assert :restarting = PM.note_live(restart)
      assert_received {:restart, _}
      assert length(bodies(ctx.ws)) == said + 1

      assert :ok = PM.boot(restart)
      refute_received {:restart, _}
      assert length(bodies(ctx.ws)) == said + 2
      assert List.last(bodies(ctx.ws)) =~ "release #{ctx.repo |> rev("live") |> String.slice(0, 7)} is live"
    end

    test "a restart that refuses is the answer, and nothing is said live", ctx do
      on_exit(fn -> :persistent_term.erase({PM, :booted}) end)
      assert :ok = PM.boot(root: ctx.repo)
      said = length(bodies(ctx.ws))

      commit!(ctx.repo, "server/lib/a.ex", "changed\n", "server: a", System.os_time(:second) + 180)
      git!(ctx.repo, ["branch", "-f", "live", "HEAD"])

      assert {:error, "no systemd"} = PM.note_live(root: ctx.repo, restart: fn _ -> {:error, "no systemd"} end)
      assert length(bodies(ctx.ws)) == said
    end

    test "a hot load moves what the server runs, so the next word isn't a restart", ctx do
      on_exit(fn -> :persistent_term.erase({PM, :booted}) end)
      assert :ok = PM.boot(root: ctx.repo)
      booted = rev(ctx.repo, "live")

      commit!(ctx.repo, "server/lib/a.ex", "changed\n", "server: a", System.os_time(:second) + 180)
      git!(ctx.repo, ["branch", "-f", "live", "HEAD"])
      to = rev(ctx.repo, "live")
      restart = [root: ctx.repo, restart: fn why -> send(self(), {:restart, why}) end]

      loaded = fn from, to ->
        send(self(), {:weighed, from, to})
        {:ok, [A]}
      end

      assert {:ok, [A]} = PM.hot_load("an older pointer", to, root: ctx.repo, hot_load: loaded)
      assert_received {:weighed, ^booted, ^to}

      assert :ok = PM.note_live(restart)
      refute_received {:restart, _}
    end

    test "a refused hot load leaves the server behind the pointer", ctx do
      on_exit(fn -> :persistent_term.erase({PM, :booted}) end)
      assert :ok = PM.boot(root: ctx.repo)

      commit!(ctx.repo, "server/lib/a.ex", "changed\n", "server: a", System.os_time(:second) + 180)
      git!(ctx.repo, ["branch", "-f", "live", "HEAD"])

      assert {:restart, "no"} =
               PM.hot_load("x", rev(ctx.repo, "live"), root: ctx.repo, hot_load: fn _, _ -> {:restart, "no"} end)

      assert :restarting = PM.note_live(root: ctx.repo, restart: fn _ -> :ok end)
    end

    test "a booted commit git can't read restarts rather than says live", ctx do
      on_exit(fn -> :persistent_term.erase({PM, :booted}) end)
      :persistent_term.put({PM, :booted}, String.duplicate("0", 40))
      said = length(bodies(ctx.ws))

      assert :restarting = PM.note_live(root: ctx.repo, restart: fn why -> send(self(), {:restart, why}) end)
      assert_received {:restart, _}
      assert length(bodies(ctx.ws)) == said
    end

    test "says nothing while a restart waits for quiet: its boot brings the code", ctx do
      {:scheduled, _} = Server.Rollout.restart(run: fn _ -> :ok end, busy: fn -> ["busy"] end, poll_ms: 60_000)
      on_exit(fn -> Server.Rollout.cancel_restart() end)

      assert :ok = PM.note_live(root: ctx.repo)
      refute Enum.any?(bodies(ctx.ws), &(&1 =~ "is live"))

      Server.Rollout.cancel_restart()
      assert :ok = PM.note_live(root: ctx.repo)
      assert List.last(bodies(ctx.ws)) =~ "is live"
    end

    test "a boot on a new release says so once, with how many changes it brought; a rollback says where from",
         ctx do
      %{ws: ws, repo: repo, live: seed, main: main} = ctx
      since = DateTime.add(DateTime.utc_now(), -60)

      assert :ok = PM.note_live(root: repo)
      assert List.last(bodies(ws)) == "release #{String.slice(seed, 0, 7)} is live"

      assert :ok = PM.note_live(root: repo)
      assert [%{payload: %{"live" => ^seed}}] = PM.live_since(since)

      git!(repo, ["branch", "-f", "live", main])
      assert :ok = PM.note_live(root: repo)
      assert List.last(bodies(ws)) == "release #{String.slice(main, 0, 7)} is live — 2 changes"

      git!(repo, ["branch", "-f", "live", seed])
      assert :ok = PM.note_live(root: repo)

      assert List.last(bodies(ws)) ==
               "release #{String.slice(seed, 0, 7)} is live — back from #{String.slice(main, 0, 7)}"

      assert [%{payload: %{"live" => ^seed}}, %{payload: %{"live" => ^main}}, _] = PM.live_since(since)
      assert [] == PM.live_since(DateTime.add(DateTime.utc_now(), 60))
    end

    test "no release cut yet records nothing", %{ws: ws, repo: repo} do
      git!(repo, ["branch", "-D", "live"])
      assert :ok = PM.note_live(root: repo)
      assert [] == PM.live_since(DateTime.add(DateTime.utc_now(), -60))
      refute Enum.any?(bodies(ws), &(&1 =~ "is live"))
    end

    test "the live release carries the subjects of the commits the cut moved over, newest last, at most 12", %{
      repo: repo,
      live: seed,
      main: main
    } do
      assert :ok = PM.note_live(root: repo)
      assert %{sha: ^seed, notes: []} = PM.live_release()

      git!(repo, ["branch", "-f", "live", main])
      assert :ok = PM.note_live(root: repo)
      assert %{sha: ^main, notes: ["office: the lamp says hello", "office: the desk says hello"]} = PM.live_release()

      now = System.os_time(:second)
      for n <- 1..14, do: commit!(repo, "f#{n}.txt", "#{n}\n", "change #{n}", now + 200 + n)
      git!(repo, ["branch", "-f", "live", "HEAD"])
      assert :ok = PM.note_live(root: repo)
      assert %{notes: notes} = PM.live_release()
      assert length(notes) == 12
      assert List.last(notes) == "change 14"

      git!(repo, ["branch", "-f", "live", seed])
      assert :ok = PM.note_live(root: repo)
      assert %{sha: ^seed, notes: []} = PM.live_release()
    end
  end

  describe "note_live/1 wakes the threads blocked on a ticket closed since" do
    test "a new release going live wakes them", ctx do
      %{ws: ws, repo: repo, main: main} = ctx
      {:ok, ticket} = Server.Tickets.file(%{workspace_id: ws.id, title: "worktrees are read-only"})
      {:ok, agent} = Server.Staff.register_agent(%{name: "yu", mandate: "build", engine: "fresh"})
      {:ok, t} = Channel.open_thread(%{title: "work", workspace_id: ws.id, agent_id: agent.id})
      {:ok, _} = Server.Blocked.declare(ticket.id, t.id, "yu", "ro")

      assert :ok = PM.note_live(root: repo)
      assert Server.Blocked.blocked?(t.id)

      {:ok, _} = Server.Tickets.update(Server.Tickets.get(ticket.id), %{status: "done"})
      git!(repo, ["branch", "-f", "live", main])
      assert :ok = PM.note_live(root: repo)

      refute Server.Blocked.blocked?(t.id)
      assert List.last(Channel.thread_messages(t)).body =~ "@yu the blocker ##{ticket.id}"
    end
  end

  describe "note_live/1 and a blocker closed after the pointer moved" do
    test "stays blocked until the next release", ctx do
      %{ws: ws, repo: repo, main: main} = ctx
      {:ok, ticket} = Server.Tickets.file(%{workspace_id: ws.id, title: "ro"})
      {:ok, agent} = Server.Staff.register_agent(%{name: "yu", mandate: "build", engine: "fresh"})
      {:ok, t} = Channel.open_thread(%{title: "work", workspace_id: ws.id, agent_id: agent.id})
      {:ok, _} = Server.Blocked.declare(ticket.id, t.id, "yu", "ro")

      cut = DateTime.utc_now() |> DateTime.add(-120) |> DateTime.to_iso8601()
      git!(repo, ["branch", "-f", "live", main], [{"GIT_COMMITTER_DATE", cut}])
      {:ok, _} = Server.Tickets.update(Server.Tickets.get(ticket.id), %{status: "done"})
      closed = DateTime.utc_now() |> DateTime.add(-60) |> DateTime.truncate(:second)
      Repo.update_all(from(x in Server.Ticket, where: x.id == ^ticket.id), set: [closed_at: closed])

      assert :ok = PM.note_live(root: repo)
      assert Server.Blocked.blocked?(t.id)
    end
  end

  defp workline_merged!(ws, title, at) do
    {:ok, t} =
      Server.Workline.open(%{title: title, slug: "w#{System.unique_integer([:positive])}", workspace_id: ws.id})

    Repo.insert!(%Server.Event{
      thread_id: t.id,
      kind: "stage_advanced",
      correlation: "workline:#{t.slug}",
      detail: %{"from" => "review", "to" => "landed"},
      created_at: DateTime.truncate(at, :second)
    })

    t
  end
end
