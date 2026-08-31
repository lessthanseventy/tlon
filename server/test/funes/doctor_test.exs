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
               "collection",
               "event",
               "fact",
               "habit",
               "issue",
               "message",
               "note",
               "project",
               "question",
               "session",
               "thread",
               "ticket",
               "todo",
               "workspace"
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

  test "refuses an unknown table rather than interpolating it" do
    assert_raise ArgumentError, ~r/no such table/, fn ->
      Doctor.table_to_jsonl("collection; DROP TABLE collection")
    end
  end
end
