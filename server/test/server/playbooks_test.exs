defmodule Server.PlaybooksTest do
  # Playbooks: named procedures with success criteria; promote turns a solved thread into one.
  use ExUnit.Case, async: false

  alias Server.Channel
  alias Server.Dossier
  alias Server.Playbooks

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "define/list/get_by_name — a slug name, steps required, duplicates refused" do
    assert {:ok, p} =
             Playbooks.define(%{
               name: "release-server",
               summary: "ship the release",
               steps: "1. mise run server:check\n2. mise run server:restart",
               success: "- service active"
             })

    assert p.name == "release-server"
    assert [%{name: "release-server"}] = Playbooks.list()
    assert Playbooks.get_by_name("release-server").steps =~ "server:restart"
    assert {:error, cs} = Playbooks.define(%{name: "release-server", steps: "x"})
    assert {"has already been taken", _} = cs.errors[:name]
    assert {:error, cs} = Playbooks.define(%{name: "Not A Slug", steps: "x"})
    assert cs.errors[:name]
    assert {:error, _} = Playbooks.define(%{name: "no-steps"})
  end

  test "promote/2 builds steps from the thread's done todos, in order, and success from its passed checks" do
    {:ok, t} = Channel.open_thread(%{title: "wire the toast"})
    {:ok, a} = Dossier.add_todo(%{thread_id: t.id, text: "find the poll"})
    {:ok, b} = Dossier.add_todo(%{thread_id: t.id, text: "add notify-send"})
    {:ok, _} = Dossier.add_todo(%{thread_id: t.id, text: "still open"})
    {:ok, _} = Dossier.complete_todo(a)
    {:ok, _} = Dossier.complete_todo(b)
    {:ok, _} = Dossier.record_check(%{thread_id: t.id, cmd: "mise run shell:check", exit: 0, tail: "ok"})
    {:ok, _} = Dossier.record_check(%{thread_id: t.id, cmd: "mise run flake:check", exit: 1, tail: "boom"})

    assert {:ok, p} = Playbooks.promote(t, %{name: "wire-a-toast", author: "hronir"})
    assert p.summary == "wire the toast"
    assert p.steps == "1. find the poll\n2. add notify-send"
    assert p.success == "- `mise run shell:check` passes"
    assert p.source_thread_id == t.id
    assert p.author == "hronir"
  end

  test "promote/2 with no done work and no steps is :nothing_to_promote; explicit steps win" do
    {:ok, t} = Channel.open_thread(%{title: "empty"})
    assert {:error, :nothing_to_promote} = Playbooks.promote(t, %{name: "empty"})
    assert {:ok, p} = Playbooks.promote(t, %{name: "by-hand", steps: "1. do it", success: "- it is done"})
    assert p.steps == "1. do it"
  end
end
