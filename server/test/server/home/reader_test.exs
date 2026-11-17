defmodule Server.Home.ReaderTest do
  use ExUnit.Case, async: false

  alias Server.Home.Reader

  test "a reminder's time is read as local and said back as local" do
    reply = ~s(sure:\n{"kind":"reminder","text":" call the dentist ","at":"2026-11-20T09:00","amends":false}\n)

    assert {:ok, %{kind: "reminder", text: "call the dentist", due_at: %DateTime{}, amends: false} = reading} =
             Reader.parse(reply)

    assert Reader.say(reading) == "I'll remind you Fri 20 Nov 09:00: call the dentist"
  end

  test "a reminder with no time it can read is a note" do
    assert {:ok, %{kind: "todo", due_at: nil}} = Reader.parse(~s({"kind":"reminder","text":"milk","at":"friday"}))

    assert {:ok, %{kind: "note", text: "milk", amends: true} = note} =
             Reader.parse(~s({"kind":"note","text":"milk","at":null,"amends":true}))

    assert Reader.say(note) == "noted: milk"
  end

  test "a reminder that repeats says how, and says so back" do
    reply = ~s({"kind":"reminder","text":"bins","at":"2026-11-19T19:00","every":"week","ids":[],"amends":false})

    assert {:ok, %{kind: "reminder", every: "week"} = reading} = Reader.parse(reply)
    assert Reader.say(reading) == "I'll remind you Thu 19 Nov 19:00, then every week: bins"
    assert {:ok, %{every: nil}} = Reader.parse(String.replace(reply, "week", "fortnight"))
  end

  test "what the operator wants of the helper needs no text, but an answer does" do
    assert {:ok, %{kind: "done", ids: [3, 4]}} = Reader.parse(~s({"kind":"done","ids":[3,"x",4]}))
    assert {:ok, %{kind: "list", ids: []}} = Reader.parse(~s({"kind":"list","text":""}))

    assert {:ok, %{kind: "answer", text: "On the fridge."}} =
             Reader.parse(~s({"kind":"answer","text":"On the fridge."}))

    assert Reader.parse(~s({"kind":"answer","text":""})) == :error
  end

  test "a reply that holds no reading is none" do
    assert Reader.parse("I can't help with that") == :error
    assert Reader.parse(~s({"kind":"quest","text":"milk"})) == :error
    assert Reader.parse(~s({"kind":"note","text":"  "})) == :error
  end

  test "the model is asked with the message, the time and the jot before it" do
    dir = Path.join(System.tmp_dir!(), "reader-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    cli = Path.join(dir, "cli")
    answer = ~s({"kind":"note","text":"oat milk","at":null,"amends":true})
    File.write!(cli, "#!/bin/sh\ncat > #{dir}/asked\necho '#{answer}'\n")
    File.chmod!(cli, 0o755)
    Application.put_env(:server, :home_reader_cmd, cli)

    on_exit(fn ->
      Application.delete_env(:server, :home_reader_cmd)
      File.rm_rf!(dir)
    end)

    previous = %Server.Jot{body: "milk", kind: "note", text: "milk"}

    context = %{
      previous: previous,
      open: [%Server.Jot{id: 12, kind: "todo", text: "buy bread"}],
      notes: ["the bins go out thursday"]
    }

    assert Reader.read("no, oat milk", context) ==
             {:ok, %{kind: "note", text: "oat milk", due_at: nil, every: nil, ids: [], amends: true}}

    assert File.read!(Path.join(dir, "asked")) =~ "OPEN:\n12: to do: buy bread\nNOTES:\n- the bins go out thursday"
    asked = File.read!(Path.join(dir, "asked"))
    assert asked =~ "MESSAGE: no, oat milk"
    assert asked =~ "PREVIOUS MESSAGE: milk"
    assert asked =~ "IT WAS FILED AS: noted: milk"
    assert asked =~ to_string(Date.utc_today().year)
  end
end
