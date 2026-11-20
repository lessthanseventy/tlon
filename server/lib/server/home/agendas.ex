defmodule Server.Home.Agendas do
  @moduledoc """
  What the home does with agendas (`Server.Agenda`) when the operator says something about one, and
  at the time one comes round. A reading from `Server.Home.Reader` names its agenda: an existing one
  (the reader matched it loosely against the names it was shown) or a new name, which starts a new
  agenda, and the reply says so. Nothing here asks for an answer: a pile is told once, ahead of its
  time (`tell/4`), and that is all. The piles of people and the one by the door are filed on the same
  way (`person/3`, `person_note/3`, `door/3`, `door_ask/2`); they are never told.
  """

  alias Server.Agenda
  alias Server.Home.Clock
  alias Server.Jot

  @doc """
  File the kept `jot` as the note `reading.text` on the pile of the agenda `reading.agenda`, at `now`,
  starting the agenda when there is none by that name. The reply the helper says.
  """
  @spec file(Jot.t(), map(), DateTime.t()) :: String.t()
  def file(%Jot{via: via} = jot, %{agenda: name, text: text}, now) do
    {state, agenda} = find(via, name, %{}, now)
    Agenda.note(agenda, jot, text, now)
    pile = Agenda.say_pile(agenda, length(Jot.agenda_notes(agenda.id)))
    started(state, agenda, pile)
  end

  @doc """
  File the kept `jot` as the note `reading.text` on the pile by the door, at `now`. The reply the helper says.
  """
  @spec door(Jot.t(), map(), DateTime.t()) :: String.t()
  def door(%Jot{via: via} = jot, %{text: text}, now) do
    door = Agenda.ensure_door(via, now)
    Agenda.note(door, jot, text, now)
    "By the door (#{length(Jot.agenda_notes(door.id))})."
  end

  @doc "Answer the ask of what is by the door: the `jot` is kept as talk, nothing to keep. The reply the helper says."
  @spec door_ask(Jot.t(), DateTime.t()) :: String.t()
  def door_ask(%Jot{via: via} = jot, now) do
    Jot.file(jot, %{kind: "talk", text: nil, due_at: nil}, now)

    via
    |> Agenda.door()
    |> pile()
    |> case do
      [] -> "Nothing by the door."
      notes -> Enum.join(["By the door (#{length(notes)}):" | Enum.map(notes, &"• #{&1.text}")], "\n")
    end
  end

  @doc """
  Make the person `reading.person` with the birthday `reading.birthday`, or change the birthday of the one
  there is, at `now`: the `jot` is kept as talk, nothing to keep. The reply the helper says.
  """
  @spec person(Jot.t(), map(), DateTime.t()) :: String.t()
  def person(%Jot{via: via} = jot, %{person: name, birthday: birthday}, now) do
    Jot.file(jot, %{kind: "talk", text: nil, due_at: nil}, now)
    {state, person} = find_person(via, name, %{birthday: birthday}, now)

    case state do
      :new -> "Added #{person.name}. Birthday: #{birthday_said(birthday)}."
      :old -> change_birthday(person, birthday, now)
    end
  end

  @doc """
  File the kept `jot` as the note `reading.text` on the pile of the person `reading.person`, made when
  they are not known, at `now`. The reply the helper says.
  """
  @spec person_note(Jot.t(), map(), DateTime.t()) :: String.t()
  def person_note(%Jot{via: via} = jot, %{person: name, text: text}, now) do
    {state, person} = find_person(via, name, %{}, now)
    Agenda.note(person, jot, text, now)
    noted = "Noted for #{person.name} (#{length(Jot.agenda_notes(person.id))})."
    if state == :new, do: "Added #{person.name}. #{noted}", else: noted
  end

  @doc """
  Answer an ask about an agenda (`agenda_set`, `agenda_show`, `agenda_past`, `agenda_clear`) from
  `reading`, at `now`: the `jot` is kept as talk, nothing to keep. The reply the helper says.
  """
  @spec ask(Jot.t(), map(), DateTime.t()) :: String.t()
  def ask(%Jot{via: via} = jot, %{kind: kind, agenda: name} = reading, now) do
    Jot.file(jot, %{kind: "talk", text: nil, due_at: nil}, now)
    answer(kind, via, name, reading, now)
  end

  @doc """
  Say in `chat` the pile of each agenda from `via` whose time is within the lead at `now`, once, and
  move on the agendas whose time has gone by. An agenda whose pile is empty is passed without a word. With no
  chat (`""`) it is only recorded as told, which is what the desktop raises (`Server.Home.told_agendas/1`).
  A message that did not go out is said at the next poll.
  """
  @spec tell(String.t(), String.t(), (String.t(), String.t(), keyword() -> term()) | nil, DateTime.t()) :: :ok
  def tell(via, chat, say, now) do
    for agenda <- Agenda.due(via, now),
        [_ | _] = notes <- [Jot.agenda_notes(agenda.id)],
        chat == "" or say.(chat, Agenda.say_told(agenda, notes), []) == :ok do
      Agenda.told(agenda, now)
    end

    Agenda.advance(via, now)
  end

  defp answer("agenda_show", via, name, _reading, _now) do
    case Agenda.named(via, name) do
      nil -> missing(name)
      agenda -> Agenda.say_list(agenda, Jot.agenda_notes(agenda.id))
    end
  end

  defp answer("agenda_past", via, name, _reading, _now) do
    with %Agenda{} = agenda <- Agenda.named(via, name),
         [%Jot{done_at: at} | _] = notes <- Jot.agenda_archived(agenda.id) do
      day = at |> Clock.local() |> NaiveDateTime.to_date() |> Calendar.strftime("%a %-d %b")
      Enum.join(["On the #{agenda.name} pile when it was cleared, #{day}:" | Enum.map(notes, &"• #{&1.text}")], "\n")
    else
      nil -> missing(name)
      [] -> "Nothing has been cleared from the #{name} pile."
    end
  end

  defp answer("agenda_clear", via, name, _reading, now) do
    case Agenda.named(via, name) do
      nil -> missing(name)
      agenda -> cleared(agenda, Agenda.clear(agenda, now))
    end
  end

  defp answer("agenda_set", via, name, reading, now) do
    rhythm =
      for {key, value} <- [next_at: reading.due_at, every: reading.every], value != nil, into: %{}, do: {key, value}

    case Agenda.named(via, name) do
      nil ->
        {state, agenda} = find(via, name, rhythm, now)
        started(state, agenda, rhythm_said(agenda, rhythm))

      agenda when rhythm == %{} ->
        rhythm_said(agenda, rhythm)

      agenda ->
        {:ok, agenda} = Agenda.edit(agenda, rhythm, now)
        rhythm_said(agenda, rhythm)
    end
  end

  defp find(via, name, rhythm, now) do
    case Agenda.named(via, name) do
      %Agenda{} = agenda ->
        {:old, agenda}

      nil ->
        case Agenda.create(via, Agenda.clean(name), rhythm, now) do
          {:ok, agenda} -> {:new, agenda}
          {:error, _taken} -> {:old, Agenda.named(via, name)}
        end
    end
  end

  defp find_person(via, name, attrs, now) do
    case Agenda.named(via, name, "person") do
      %Agenda{} = person ->
        {:old, person}

      nil ->
        case Agenda.create(via, Agenda.clean(name), Map.put(attrs, :kind, "person"), now) do
          {:ok, person} -> {:new, person}
          {:error, _taken} -> {:old, Agenda.named(via, name, "person")}
        end
    end
  end

  defp change_birthday(%Agenda{birthday: birthday} = person, birthday, _now),
    do: "#{person.name}'s birthday was already #{birthday_said(birthday)}."

  defp change_birthday(person, birthday, now) do
    {:ok, person} = Agenda.edit(person, %{birthday: birthday}, now)
    "Birthday for #{person.name}: #{birthday_said(person.birthday)}."
  end

  defp birthday_said(birthday) do
    [month, day] = birthday |> String.slice(-5, 5) |> String.split("-") |> Enum.map(&String.to_integer/1)
    Calendar.strftime(Date.new!(2000, month, day), "%B %-d")
  end

  defp pile(nil), do: []
  defp pile(%Agenda{id: id}), do: Jot.agenda_notes(id)

  defp started(:new, agenda, said), do: "Started a new agenda, #{agenda.name}. #{said}"
  defp started(:old, _agenda, said), do: said

  defp rhythm_said(%Agenda{every: every, next_at: nil} = agenda, _rhythm) when is_binary(every),
    do: Agenda.say_rhythm(agenda) <> " When is the next one?"

  defp rhythm_said(agenda, rhythm) when rhythm == %{},
    do: Agenda.say_rhythm(agenda) <> " Tell me when it is, or how often, to set it."

  defp rhythm_said(agenda, _rhythm), do: Agenda.say_rhythm(agenda)

  defp cleared(agenda, 0), do: "The #{agenda.name} pile was already empty."
  defp cleared(agenda, count), do: "Cleared the #{agenda.name} pile (#{count} kept, done)."

  defp missing(name), do: "I don't have an agenda called #{name}."
end
