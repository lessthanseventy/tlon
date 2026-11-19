defmodule Server.Home.ReaderTest do
  use ExUnit.Case, async: false

  alias Server.Home.Reader

  test "a reminder's time is read as local and said back as local" do
    reply = ~s(sure:\n{"kind":"reminder","text":" call the dentist ","at":"2026-11-20T09:00","amends":false}\n)

    assert {:ok, %{kind: "reminder", text: "call the dentist", due_at: %DateTime{}, amends: false} = reading} =
             Reader.parse(reply)

    assert Reader.say(reading) == "I'll remind you Fri 20 Nov 09:00: call the dentist"
  end

  describe "agendas" do
    test "\"for retro: the deploy took three tries\" is a note on the agenda retro" do
      reply = ~s({"kind":"agenda","agenda":" retro ","text":"the deploy took three tries","at":null})

      assert {:ok, %{kind: "agenda", agenda: "retro", text: "the deploy took three tries", due_at: nil}} =
               Reader.parse(reply)
    end

    test "an agenda reading with no agenda named, or no text, is no reading" do
      assert :error = Reader.parse(~s({"kind":"agenda","text":"x"}))
      assert :error = Reader.parse(~s({"kind":"agenda","agenda":"  ","text":"x"}))
      assert :error = Reader.parse(~s({"kind":"agenda","agenda":"retro","text":" "}))
      assert :error = Reader.parse(~s({"kind":"agenda_show"}))
    end

    test "\"retro is every other Thursday at 2\" sets a rhythm: a time and an every" do
      reply = ~s({"kind":"agenda_set","agenda":"retro","text":"","at":"2026-11-19T14:00","every":"2 weeks"})

      assert {:ok, %{kind: "agenda_set", agenda: "retro", every: "2 week", due_at: %DateTime{} = at}} =
               Reader.parse(reply)

      assert Server.Home.Clock.say(at) == "Thu 19 Nov 14:00"

      assert {:ok, %{agenda: "1:1 with Sam", every: "week", due_at: %DateTime{}}} =
               Reader.parse(~s({"kind":"agenda_set","agenda":"1:1 with Sam","at":"2026-11-23T10:00","every":"week"}))

      assert {:ok, %{agenda: "retro", every: nil, due_at: nil}} =
               Reader.parse(~s({"kind":"agenda_set","agenda":"retro","every":"fortnight"}))
    end

    test "what is on a pile, what was, and clearing it are asks that need no text" do
      for kind <- ["agenda_show", "agenda_past", "agenda_clear"] do
        assert {:ok, %{kind: ^kind, agenda: "retro", text: ""}} =
                 Reader.parse(~s({"kind":"#{kind}","agenda":"retro"}))
      end
    end
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

  test "a repeat is every N days, weeks or months, and says so back" do
    reply = ~s({"kind":"reminder","text":"haircut","at":"2026-11-19T19:00","every":"6 week"})

    assert {:ok, %{every: "6 week"} = reading} = Reader.parse(reply)
    assert Reader.say(reading) == "I'll remind you Thu 19 Nov 19:00, then every 6 weeks: haircut"
    assert {:ok, %{every: "3 month"}} = Reader.parse(String.replace(reply, "6 week", "3 months"))
    assert {:ok, %{every: "week"}} = Reader.parse(String.replace(reply, "6 week", "1 week"))
    assert {:ok, %{every: nil}} = Reader.parse(String.replace(reply, "6 week", "0 week"))
  end

  test "a kept reading may name the open thing it updates, and only a to-do or a reminder can" do
    todo = ~s({"kind":"todo","text":"get quotes by friday","updates":7})
    assert {:ok, %{kind: "todo", updates: 7}} = Reader.parse(todo)
    assert {:ok, %{updates: 7}} = Reader.parse(~s({"kind":"reminder","text":"x","at":"2026-11-19T19:00","updates":7}))
    refute Map.has_key?(elem(Reader.parse(~s({"kind":"note","text":"x","updates":7})), 1), :updates)
    refute Map.has_key?(elem(Reader.parse(~s({"kind":"todo","text":"x","updates":"7"})), 1), :updates)
  end

  test "an answer names the things in words: a number the model let out is put right" do
    open = [
      %Server.Jot{id: 7, text: "get mover quotes", kind: "todo"},
      %Server.Jot{id: 9, text: "buy milk", kind: "todo"}
    ]

    assert Reader.unnumber("item 7 is due, and #9 too", open) == "get mover quotes is due, and buy milk too"
    assert Reader.unnumber("Item #7?", open) == "get mover quotes?"
    assert Reader.unnumber("PR #901 landed; item 5 is odd", open) == "PR #901 landed; item 5 is odd"
    assert Reader.unnumber("nothing to fix", open) == "nothing to fix"
  end

  test "what the operator wants of the helper needs no text, but an answer does" do
    assert {:ok, %{kind: "done", ids: [3, 4]}} = Reader.parse(~s({"kind":"done","ids":[3,"x",4]}))
    assert {:ok, %{kind: "delete", ids: [3], text: ""}} = Reader.parse(~s({"kind":"delete","ids":[3,"x"]}))
    assert {:ok, %{kind: "list", ids: []}} = Reader.parse(~s({"kind":"list","text":""}))

    assert {:ok, %{kind: "answer", text: "On the fridge."}} =
             Reader.parse(~s({"kind":"answer","text":"On the fridge."}))

    assert Reader.parse(~s({"kind":"answer","text":""})) == :error
  end

  test "an outcome of several steps is a project with at most five steps, and says them back" do
    reply = ~s({"kind":"project","text":"plan mom's birthday","steps":["book a table"," ","ask dad","a","b","c","d"]})

    assert {:ok, %{kind: "project", text: "plan mom's birthday", steps: steps, due_at: nil} = reading} =
             Reader.parse(reply)

    assert steps == ["book a table", "ask dad", "a", "b", "c"]

    assert Reader.say(reading) == "project: plan mom's birthday\nfirst step: book a table\nthen: ask dad, a, b, c"

    assert Reader.say(%{reading | steps: ["call"]}) == "project: plan mom's birthday\nfirst step: call"
  end

  test "a project with no steps is a to-do, and a waiting-on with no one named is too" do
    assert {:ok, %{kind: "todo", text: "sort the car"}} = Reader.parse(~s({"kind":"project","text":"sort the car"}))
    assert {:ok, %{kind: "todo"}} = Reader.parse(~s({"kind":"project","text":"x","steps":"call"}))
    assert {:ok, %{kind: "todo", text: "the photos"}} = Reader.parse(~s({"kind":"waiting","text":"the photos"}))
  end

  test "a waiting-on says who and what, and when it will ask" do
    assert {:ok, %{kind: "waiting", who: "Sam", text: "the photos"} = reading} =
             Reader.parse(~s({"kind":"waiting","text":"the photos","who":" Sam "}))

    assert Reader.say(reading) == "waiting on Sam for the photos. I'll ask in 3 days."
    assert Reader.say(%Server.Jot{kind: "waiting", text: "the photos", waiting_on: "Sam"}) == Reader.say(reading)
  end

  test "asking what now, with the minutes there are, and what is on someday, needs no text" do
    assert {:ok, %{kind: "now", minutes: 10}} = Reader.parse(~s({"kind":"now","minutes":10}))
    assert {:ok, %{kind: "now"} = reading} = Reader.parse(~s({"kind":"now","minutes":"ten"}))
    refute Map.has_key?(reading, :minutes)
    refute Map.has_key?(elem(Reader.parse(~s({"kind":"now","minutes":0})), 1), :minutes)
    assert {:ok, %{kind: "someday", ids: []}} = Reader.parse(~s({"kind":"someday"}))
  end

  test "a to-do's size, project, what was assumed, the one question and what to revive are kept when they are valid" do
    reply =
      ~s({"kind":"todo","text":"email Sam","mins":10,"project":4,"assumed":"Sam is Sam Lee","ask":"Which day? Or later?","revive":[3,"x"]})

    assert {:ok, %{mins: 10, project: 4, assumed: "Sam is Sam Lee", ask: "Which day?", revive: [3]} = reading} =
             Reader.parse(reply)

    assert Reader.reply(reading) == "to do: email Sam\nI took it that Sam is Sam Lee.\nWhich day?"

    assert {:ok, bare} =
             Reader.parse(~s({"kind":"todo","text":"x","mins":7,"project":"4","assumed":" ","ask":5,"revive":[]}))

    assert bare == %{kind: "todo", text: "x", due_at: nil, every: nil, ids: [], amends: false}
  end

  test "a project is never asked about, and a note carries no size or project" do
    assert {:ok, reading} = Reader.parse(~s({"kind":"project","text":"x","steps":["a"],"ask":"When?"}))
    refute Map.has_key?(reading, :ask)

    assert {:ok, note} = Reader.parse(~s({"kind":"note","text":"x","mins":10,"project":2}))
    assert note == %{kind: "note", text: "x", due_at: nil, every: nil, ids: [], amends: false}
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
