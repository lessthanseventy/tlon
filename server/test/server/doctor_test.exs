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
               "habit",
               "issue",
               "message",
               "note",
               "playbook",
               "project",
               "question",
               "session",
               "thread",
               "ticket",
               "ticket_link",
               "ticket_thread",
               "todo",
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
    dir = Path.join(System.tmp_dir!(), "doctor-export-#{System.unique_integer([:positive])}")
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
