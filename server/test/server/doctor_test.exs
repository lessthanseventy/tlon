defmodule Server.DoctorTest do
  use ExUnit.Case, async: false

  alias Server.Doctor
  alias Server.Repo

  test "reports integrity ok on a healthy database" do
    assert Doctor.integrity_check() == "ok"
  end

  test "lists the domain tables and excludes sqlite internals and the migration ledger" do
    assert Doctor.tables() ==
             [
               "agent",
               "channel",
               "collection",
               "event",
               "fact",
               "fun_with_flags_toggles",
               "generated_part",
               "generator_call",
               "habit",
               "health_since",
               "issue",
               "message",
               "need_dismissal",
               "need_heard",
               "need_routing",
               "note",
               "note_revision",
               "playbook",
               "project",
               "quest",
               "question",
               "routine",
               "routine_run",
               "schedule",
               "schedule_run",
               "session",
               "thread",
               "ticket",
               "ticket_link",
               "ticket_thread",
               "todo",
               "toy_pool",
               "wake",
               "workspace",
               "workspace_agent",
               "workspace_policy",
               "workspace_repo"
             ]
  end

  test "has no pending migrations once migrated" do
    assert Doctor.pending() == []
  end

  test "exports a table to JSONL — a row that exists must appear (no false empty)" do
    Repo.query!("INSERT INTO collection (source, last_attempt) VALUES ('github-prs', '2026-08-14T00:00:00Z')")

    lines = "collection" |> Doctor.table_to_jsonl() |> String.split("\n", trim: true)
    assert length(lines) == 1

    assert JSON.decode!(hd(lines)) == %{
             "source" => "github-prs",
             "last_attempt" => "2026-08-14T00:00:00Z",
             "last_success" => nil,
             "last_error" => nil
           }
  end

  test "export/1 writes one JSONL file per table — the escape hatch on disk" do
    dir = Path.join(System.tmp_dir!(), "doctor-export-#{System.pid()}-#{System.unique_integer([:positive])}")
    Server.TestDB.clean!()

    on_exit(fn ->
      File.rm_rf!(dir)
      Repo.query!("DELETE FROM collection WHERE source = 'doctor-export'")
    end)

    Repo.query!("INSERT INTO collection (source, last_attempt) VALUES ('doctor-export', '2026-08-14T00:00:00Z')")

    paths = Doctor.export(dir)

    assert Enum.map(paths, &Path.basename/1) == Enum.map(Doctor.tables(), &"#{&1}.jsonl")
    assert Enum.all?(paths, &File.exists?/1)

    rows = dir |> Path.join("collection.jsonl") |> File.read!() |> String.split("\n", trim: true)
    assert Enum.any?(rows, &(JSON.decode!(&1)["source"] == "doctor-export"))
    assert File.read!(Path.join(dir, "ticket.jsonl")) == ""
  end

  describe "crash_dump/3" do
    setup do
      root = Path.join(System.tmp_dir!(), "doctor-crash-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      dumps = Path.join(root, "crash-dumps")
      File.mkdir_p!(dumps)
      %{root: root, dumps: dumps, dump: Path.join(root, "erl_crash.dump")}
    end

    test "none when neither place holds a dump", %{root: root, dumps: dumps} do
      assert Doctor.crash_dump(root, DateTime.utc_now(), dumps) == "none"
    end

    test "a client node's dump is dated against the start and never blamed on the service", %{root: root, dumps: dumps} do
      client = Path.join(dumps, "tlon-cli-1.dump")
      File.write!(client, "=erl_crash_dump:0.5\n")
      started = DateTime.utc_now()
      File.touch!(client, DateTime.to_unix(started) - 7200)

      line = Doctor.crash_dump(root, started, dumps)
      assert line =~ client
      assert line =~ "tlon-cli client node's, before the service started"
      refute line =~ "the last restart followed a crash"

      File.touch!(client, DateTime.to_unix(started) + 60)
      assert Doctor.crash_dump(root, started, dumps) =~ "tlon-cli client node's, written since the service started"
    end

    test "the newest dump of the two places is the one reported", %{root: root, dumps: dumps, dump: dump} do
      client = Path.join(dumps, "tlon-cli-2.dump")
      File.write!(client, "=erl_crash_dump:0.5\n")
      File.write!(dump, "=erl_crash_dump:0.5\n")
      started = DateTime.utc_now()
      File.touch!(dump, DateTime.to_unix(started) - 7200)
      File.touch!(client, DateTime.to_unix(started) - 3600)

      assert Doctor.crash_dump(root, started, dumps) =~ client
    end

    test "a dump written since the service started is flagged with its path", %{root: root, dumps: dumps, dump: dump} do
      File.write!(dump, "=erl_crash_dump:0.5\n")
      started = DateTime.add(DateTime.utc_now(), -3600)
      File.touch!(dump, DateTime.to_unix(started) + 60)

      line = Doctor.crash_dump(root, started, dumps)
      assert line =~ dump
      assert line =~ "since the service started"
      assert line =~ "another node here crashed"
    end

    test "a dump older than the service's start says so", %{root: root, dumps: dumps, dump: dump} do
      File.write!(dump, "=erl_crash_dump:0.5\n")
      started = DateTime.utc_now()
      File.touch!(dump, DateTime.to_unix(started) - 7200)

      line = Doctor.crash_dump(root, started, dumps)
      assert line =~ dump
      assert line =~ "before the service started"
      assert line =~ "the last restart followed a crash"
    end

    test "with no known start it reports the dump and its age", %{root: root, dumps: dumps, dump: dump} do
      File.write!(dump, "=erl_crash_dump:0.5\n")
      File.touch!(dump, System.os_time(:second) - 7200)

      line = Doctor.crash_dump(root, nil, dumps)
      assert line =~ dump
      assert line =~ "2h old"
      assert line =~ "service start unknown"
    end
  end

  describe "git_fetch_urls/1" do
    setup do
      repo = Path.join(System.tmp_dir!(), "doctor-git-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(repo)
      {_, 0} = System.cmd("git", ["init", "-q", repo])
      on_exit(fn -> File.rm_rf!(repo) end)
      %{repo: repo}
    end

    defp git_config!(repo, key, value), do: {_, 0} = System.cmd("git", ["-C", repo, "config", key, value])

    test "names both missing lines and the task that sets them", %{repo: repo} do
      line = Doctor.git_fetch_urls(repo)
      assert line =~ "missing"
      assert line =~ ~s|url."https://github.com/".insteadOf|
      assert line =~ ~s|url."git@github.com:".pushInsteadOf|
      assert line =~ "server:setup"
    end

    test "names only the line still missing", %{repo: repo} do
      git_config!(repo, "url.https://github.com/.insteadOf", "git@github.com:")
      line = Doctor.git_fetch_urls(repo)
      assert line =~ "missing"
      assert line =~ "pushInsteadOf"
      refute line =~ ~s|url."https://github.com/".insteadOf|
    end

    test "ok when fetch takes HTTPS and push stays on SSH", %{repo: repo} do
      git_config!(repo, "url.https://github.com/.insteadOf", "git@github.com:")
      git_config!(repo, "url.git@github.com:.pushInsteadOf", "git@github.com:")
      assert Doctor.git_fetch_urls(repo) == "ok"
    end
  end

  describe "config_lock/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "doctor-lock-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(root, ".git"))
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root, lock: Path.join([root, ".git", "config.lock"])}
    end

    test "ok when there is no lock", %{root: root} do
      assert Doctor.config_lock(root, fn -> false end) == "ok"
    end

    test "a lock older than a few minutes with no sandbox running is stale, with the rm to run", %{
      root: root,
      lock: lock
    } do
      File.write!(lock, "")
      File.touch!(lock, System.os_time(:second) - 7200)

      line = Doctor.config_lock(root, fn -> false end)
      assert line =~ lock
      assert line =~ "stale"
      assert line =~ "rm #{lock}"
    end

    test "a lock that is still young is not reported, even with no sandbox running", %{root: root, lock: lock} do
      File.write!(lock, "")

      assert Doctor.config_lock(root, fn -> false end) == "ok"
    end

    test "a lock while a sandbox is live is not reported", %{root: root, lock: lock} do
      File.write!(lock, "")
      File.touch!(lock, System.os_time(:second) - 7200)

      assert Doctor.config_lock(root, fn -> true end) == "ok"
    end
  end

  describe "untrusted_checkouts/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "doctor-trust-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root}
    end

    test "ok when there are no seat or scratch checkouts", %{root: root} do
      assert Doctor.untrusted_checkouts(root, Path.join(root, "scratch")) == "ok"
    end

    test "names a checkout whose mise.toml is untrusted, with the trust to run", %{root: root} do
      wt = Path.join([root, ".worktrees", "t1"])
      File.mkdir_p!(wt)
      File.write!(Path.join(wt, ".git"), "gitdir: nowhere\n")
      File.write!(Path.join(wt, "mise.toml"), "[env]\nDOCTOR = \"1\"\n")

      line = Doctor.untrusted_checkouts(root, Path.join(root, "scratch"))
      assert line =~ wt
      assert line =~ "mise trust"

      System.cmd("mise", ["trust", "-q", wt])
      assert Doctor.untrusted_checkouts(root, Path.join(root, "scratch")) == "ok"
    end
  end

  test "refuses an unknown table rather than interpolating it" do
    assert_raise ArgumentError, ~r/no such table/, fn ->
      Doctor.table_to_jsonl("collection; DROP TABLE collection")
    end
  end

  setup do
    Server.TestDB.clean!()
    :ok
  end
end
