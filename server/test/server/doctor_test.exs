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
               "generator_call",
               "habit",
               "issue",
               "message",
               "need_dismissal",
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

  describe "crash_dump/2" do
    setup do
      root = Path.join(System.tmp_dir!(), "doctor-crash-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(root)
      on_exit(fn -> File.rm_rf!(root) end)
      %{root: root, dump: Path.join(root, "erl_crash.dump")}
    end

    test "none when the root holds no erl_crash.dump", %{root: root} do
      assert Doctor.crash_dump(root, DateTime.utc_now()) == "none"
    end

    test "a dump written since the service started is flagged with its path", %{root: root, dump: dump} do
      File.write!(dump, "=erl_crash_dump:0.5\n")
      started = DateTime.add(DateTime.utc_now(), -3600)
      File.touch!(dump, DateTime.to_unix(started) + 60)

      line = Doctor.crash_dump(root, started)
      assert line =~ dump
      assert line =~ "since the service started"
      assert line =~ "another node here crashed"
    end

    test "a dump older than the service's start says so", %{root: root, dump: dump} do
      File.write!(dump, "=erl_crash_dump:0.5\n")
      started = DateTime.utc_now()
      File.touch!(dump, DateTime.to_unix(started) - 7200)

      line = Doctor.crash_dump(root, started)
      assert line =~ dump
      assert line =~ "before the service started"
      assert line =~ "the last restart followed a crash"
    end

    test "with no known start it reports the dump and its age", %{root: root, dump: dump} do
      File.write!(dump, "=erl_crash_dump:0.5\n")
      File.touch!(dump, System.os_time(:second) - 7200)

      line = Doctor.crash_dump(root, nil)
      assert line =~ dump
      assert line =~ "2h old"
      assert line =~ "service start unknown"
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
