defmodule Server.Home.PeopleTest do
  use ExUnit.Case, async: false

  alias Server.Agenda
  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Inbox
  alias Server.Home.Morning
  alias Server.Jot

  setup do
    Server.TestDB.clean!()
    on_exit(fn -> Application.delete_env(:server, :home_reader) end)
    me = self()

    %{
      say: fn chat, text, _opts ->
        send(me, {:said, chat, text})
        :ok
      end
    }
  end

  defp friday(time \\ ~T[08:35:00]), do: Clock.utc(NaiveDateTime.new!(~D[2026-11-20], time))

  defp person(name, birthday \\ nil) do
    {:ok, person} = Agenda.create("telegram", name, %{kind: "person", birthday: birthday}, friday())
    person
  end

  defp jot(attrs) do
    {:ok, jot} = Jot.take("telegram", System.unique_integer([:positive]), attrs.text)
    Jot.file(jot, Map.merge(%{due_at: nil}, attrs), friday())
  end

  defp note(pile, text),
    do: Agenda.note(pile, elem(Jot.take("telegram", System.unique_integer([:positive]), text), 1), text, friday())

  describe "birthdays" do
    test "are MM-DD or YYYY-MM-DD and a real day" do
      assert {:ok, "03-03"} = Agenda.birthday(" 03-03 ")
      assert {:ok, "02-29"} = Agenda.birthday("02-29")
      assert {:ok, "1990-03-03"} = Agenda.birthday("1990-03-03")

      for bad <- ["02-30", "13-01", "March 3", "3-3", "2026-02-29", "", nil, 5] do
        assert {:error, "birthday must be MM-DD or YYYY-MM-DD"} = Agenda.birthday(bad)
      end
    end

    test "next_birthday: today counts, a passed one is next year, none is none" do
      today = ~D[2026-11-20]
      assert Agenda.next_birthday("11-20", today) == ~D[2026-11-20]
      assert Agenda.next_birthday("11-27", today) == ~D[2026-11-27]
      assert Agenda.next_birthday("03-03", today) == ~D[2027-03-03]
      assert Agenda.next_birthday("1990-11-19", today) == ~D[2027-11-19]
      assert Agenda.next_birthday("02-29", today) == ~D[2027-02-28]
      assert Agenda.next_birthday("02-29", ~D[2027-12-01]) == ~D[2028-02-29]
      assert Agenda.next_birthday(nil, today) == nil
    end

    test "a pile has a kind from the three, and a person's name is free beside an agenda of that name" do
      assert {:error, "kind must be agenda, person or door"} = Agenda.create("telegram", "x", %{kind: "pet"}, friday())

      assert {:error, "birthday must be MM-DD or YYYY-MM-DD"} =
               Agenda.create("telegram", "x", %{birthday: "soon"}, friday())

      {:ok, _} = Agenda.create("telegram", "Sam", %{}, friday())
      assert %Agenda{kind: "person"} = person("sam")

      assert {:error, "there is already a person called SAM"} =
               Agenda.create("telegram", "SAM", %{kind: "person"}, friday())

      assert [%{name: "Sam", kind: "agenda"}] = Agenda.all("telegram")
      assert [%{name: "sam"}] = Agenda.all("telegram", "person")
    end
  end

  describe "Home.people/1" do
    test "orders by next birthday, then those with none by name, with the notes and the to-dos that name them" do
      person("Zed")
      person("Ana", "03-03")
      sam = person("Sam", "1985-11-27")
      person("Bob")
      note(sam, "likes kettles")

      jot(%{kind: "todo", text: "buy a kettle for Sam"})
      jot(%{kind: "reminder", text: "call SAM back", due_at: DateTime.add(friday(), 3600)})
      jot(%{kind: "waiting", text: "the photos", who: "sam"})
      jot(%{kind: "todo", text: "ask Samuel about the car"})
      jot(%{kind: "todo", text: "buy milk"})
      {:ok, done} = Jot.take("telegram", 77, "tell Sam done")
      done |> Jot.file(%{kind: "todo", text: "tell Sam done", due_at: nil}, friday()) |> Jot.done(friday())

      assert [
               %{name: "Sam", birthday: "1985-11-27", next_birthday: ~D[2026-11-27], notes: [%{text: "likes kettles"}]} =
                 sam_row,
               %{name: "Ana", birthday: "03-03", next_birthday: ~D[2027-03-03], notes: [], todos: []},
               %{name: "Bob", birthday: nil, next_birthday: nil},
               %{name: "Zed", next_birthday: nil}
             ] = Home.people(friday())

      assert ["buy a kettle for Sam", "call SAM back", "the photos"] =
               sam_row.todos |> Enum.map(& &1.text) |> Enum.sort()
    end

    test "the status holds people and the door, and agendas alone" do
      person("Sam", "11-27")
      {:ok, _} = Agenda.create("telegram", "retro", %{}, friday())

      assert %{agendas: [%{name: "retro"}], people: [%{name: "Sam"}], door: %{id: nil, notes: []}} =
               Home.status(friday())

      assert {:ok, %{text: "umbrella", kind: "note"}} = Home.door_add(" umbrella ", friday())
      assert %{door: %{id: id, notes: [%{text: "umbrella"}]}, agendas: [%{name: "retro"}]} = Home.status(friday())
      assert {:ok, %{text: "parcel"}} = Home.door_add("parcel", friday())
      assert %{door: %{id: ^id, notes: [_, _]}} = Home.status(friday())
      assert {:error, "text is required"} = Home.door_add(" ", friday())
    end

    test "a note by the door comes off by drop, not by done" do
      {:ok, %{id: note}} = Home.door_add("umbrella", friday())
      assert :error = Home.done(note, friday())
      assert {:ok, %Jot{dropped_at: %DateTime{}}} = Home.drop(note, friday())
      assert %{door: %{notes: []}} = Home.status(friday())
    end

    test "adding and editing a person through the agenda forms answers the person's row" do
      assert {:error, "birthday must be MM-DD or YYYY-MM-DD"} =
               Home.agenda_add(%{"name" => "Sam", "kind" => "person", "birthday" => "soon"}, friday())

      assert {:error, "kind is agenda or person"} = Home.agenda_add(%{"name" => "Sam", "kind" => "door"}, friday())

      assert {:ok, %{id: id, name: "Sam", birthday: "11-27", next_birthday: ~D[2026-11-27], notes: [], todos: []}} =
               Home.agenda_add(%{"name" => "Sam", "kind" => "person", "birthday" => "11-27"}, friday())

      assert {:ok, %{birthday: "1985-03-03", next_birthday: ~D[2027-03-03]}} =
               Home.agenda_edit(id, %{"birthday" => "1985-03-03"}, friday())

      assert {:ok, %{birthday: nil, next_birthday: nil}} = Home.agenda_edit(id, %{"birthday" => nil}, friday())
      assert {:ok, %{text: "a kettle"}} = Home.agenda_note(id, "a kettle", friday())
      assert {:ok, %{id: ^id, name: "Sam"}} = Home.agenda_drop(id, friday())
    end
  end

  describe "the morning message" do
    test "says a birthday today and one a week ahead, with the notes as ideas, and nothing for the days between" do
      today = person("Ana", "11-20")
      sam = person("Sam", "1985-11-27")
      person("Cy", "11-21")
      person("Di", "11-26")
      note(sam, "a kettle")
      note(sam, "a book")
      note(today, "dinner")

      assert {text, []} = Morning.compose("telegram", friday(), [])

      assert text ==
               """
               Good morning.

               Birthdays:
               • Ana's birthday is today. Ideas: dinner
               • Sam's birthday is next Friday. Ideas: a kettle; a book\
               """

      assert {^text, []} = Morning.plain("telegram", friday(), friday(~T[08:30:00]), [])
    end

    test "a person with no notes has no ideas, and a person with no birthday is not said" do
      person("Sam", "11-27")
      person("Bob")

      assert {"Good morning.\n\nBirthdays:\n• Sam's birthday is next Friday", []} =
               Morning.compose("telegram", friday(), [])
    end

    test "the day before and after are quiet, and nothing is said when no one is near" do
      person("Cy", "11-19")
      person("Di", "11-28")
      assert Morning.compose("telegram", friday(), []) == nil
    end
  end

  describe "the chat" do
    defp say_it(text, reading, say, id) do
      Application.put_env(:server, :home_reader, fn ^text, _context ->
        {:ok, Map.merge(%{text: "", due_at: nil, every: nil, ids: [], amends: false}, reading)}
      end)

      Inbox.hear([%{id: id, chat: "42", text: text}], "telegram", "42", say)
      assert_receive {:said, "42", reply}
      reply
    end

    test "things go by the door, and heading out is answered with the pile", %{say: say} do
      assert say_it("what's by the door", %{kind: "door_show"}, say, 1) == "Nothing by the door."
      assert Agenda.door("telegram") == nil

      assert say_it("by the door: umbrella", %{kind: "door", text: "umbrella"}, say, 2) == "By the door (1)."

      assert say_it("errand: return the parcel", %{kind: "door", text: "return the parcel"}, say, 3) ==
               "By the door (2)."

      assert say_it("heading out", %{kind: "door_show"}, say, 4) ==
               "By the door (2):\n• umbrella\n• return the parcel"

      assert %Agenda{kind: "door", id: id} = Agenda.door("telegram")
      assert ["umbrella", "return the parcel"] = Enum.map(Jot.agenda_notes(id), & &1.text)
      assert Jot.notes("telegram", 20) == []
      assert Agenda.all("telegram") == []
    end

    test "a birthday makes or changes the person, a gift idea is a note on their pile", %{say: say} do
      assert say_it("Sam's birthday is March 3", %{kind: "person", person: "Sam", birthday: "03-03"}, say, 1) ==
               "Added Sam. Birthday: March 3."

      assert say_it("Sam's birthday is March 3", %{kind: "person", person: "sam", birthday: "03-03"}, say, 2) ==
               "Sam's birthday was already March 3."

      assert say_it("Sam's birthday is March 4 1985", %{kind: "person", person: "sam", birthday: "1985-03-04"}, say, 3) ==
               "Birthday for Sam: March 4."

      assert say_it("gift idea for Sam: a kettle", %{kind: "person_note", person: "Sam", text: "a kettle"}, say, 4) ==
               "Noted for Sam (1)."

      assert say_it("gift idea for Ana: a book", %{kind: "person_note", person: "Ana", text: "a book"}, say, 5) ==
               "Added Ana. Noted for Ana (1)."

      assert [%{name: "Sam", birthday: "1985-03-04"}, %{name: "Ana", birthday: nil}] = Agenda.all("telegram", "person")
      assert Agenda.all("telegram") == []
      assert Jot.notes("telegram", 20) == []
    end
  end
end
