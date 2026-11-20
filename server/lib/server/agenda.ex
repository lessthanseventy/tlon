defmodule Server.Agenda do
  @moduledoc """
  A standing pile of notes for an occasion that comes round: "retro", "1:1 with Sam", "weekly". Its
  notes are notes of the home (`Server.Jot`, `agenda_id`) that live on the agenda, in none of the plain
  lists. An agenda may have a rhythm: `every` (as `Server.Home.Clock.every/1` reads it) and `next_at`,
  the next time it comes round (no `every`: a one-off time, or none). Fifteen minutes before `next_at` the
  home tells the pile once (`due/2`, `told/2`); an hour after it the time moves on by the rhythm
  (`advance/2`), so the pile can still be added to while the occasion is on. Clearing archives the
  notes (done, with the date) and the agenda stands, empty.

  The same pile also holds two other things, told apart by `kind`: a `person` (their notes, and an
  optional `birthday`, `MM-DD` or `YYYY-MM-DD`) and the `door`, the one pile per `via` of what to take
  along and errands for the next time the operator goes out. Everything above is of `agenda`s alone:
  `all/1` and `named/2` give those, `all/2` and `named/3` the kind asked for.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.Home.Clock
  alias Server.Jot
  alias Server.Repo

  @type t :: %__MODULE__{}

  @lead_min 15
  @linger_min 60
  @max_name 80
  @kinds ["agenda", "person", "door"]
  @door_name "by the door"
  @bad_birthday "birthday must be MM-DD or YYYY-MM-DD"

  schema "home_agenda" do
    field :via, :string
    field :kind, :string, default: "agenda"
    field :birthday, :string
    field :name, :string
    field :every, :string
    field :every_day, :integer
    field :next_at, :utc_datetime
    field :told_for, :utc_datetime
    field :told_at, :utc_datetime
  end

  @doc "The agendas from `via`, oldest first."
  @spec all(String.t()) :: [t()]
  def all(via), do: all(via, "agenda")

  @doc "The piles of `kind` (`agenda`, `person` or `door`) from `via`, oldest first."
  @spec all(String.t(), String.t()) :: [t()]
  def all(via, kind), do: Repo.all(from(a in __MODULE__, where: a.via == ^via and a.kind == ^kind, order_by: a.id))

  @doc "The pile `id` from `via`, of any kind, nil when there is none."
  @spec get(String.t(), integer()) :: t() | nil
  def get(via, id), do: Repo.get_by(__MODULE__, via: via, id: id)

  @doc "The agenda called `name` (any case) from `via`, nil when there is none."
  @spec named(String.t(), String.t()) :: t() | nil
  def named(via, name), do: named(via, name, "agenda")

  @doc "The pile of `kind` called `name` (any case) from `via`, nil when there is none."
  @spec named(String.t(), String.t(), String.t()) :: t() | nil
  def named(via, name, kind) do
    key = String.downcase(name)

    Repo.one(from(a in __MODULE__, where: a.via == ^via and a.kind == ^kind and fragment("lower(?)", a.name) == ^key))
  end

  @doc "The door pile of `via`, nil before anything was put on it."
  @spec door(String.t()) :: t() | nil
  def door(via), do: named(via, @door_name, "door")

  @doc "The door pile of `via`, made at `now` when there is none yet."
  @spec ensure_door(String.t(), DateTime.t()) :: t()
  def ensure_door(via, now) do
    with nil <- door(via),
         {:error, _taken} <- create(via, @door_name, %{kind: "door"}, now) do
      door(via)
    else
      %__MODULE__{} = door -> door
      {:ok, door} -> door
    end
  end

  @doc """
  A birthday as it is kept: `MM-DD` (February 29 allowed), or `YYYY-MM-DD` when the year is known.
  `{:error, reason}` for anything else.
  """
  @spec birthday(term()) :: {:ok, String.t()} | {:error, String.t()}
  def birthday(text) when is_binary(text) do
    text = String.trim(text)

    with [_, year, month, day] <- Regex.run(~r/^(?:(\d{4})-)?(\d{2})-(\d{2})$/, text),
         {:ok, _date} <-
           Date.new(
             if(year == "", do: 2000, else: String.to_integer(year)),
             String.to_integer(month),
             String.to_integer(day)
           ) do
      {:ok, text}
    else
      _ -> {:error, @bad_birthday}
    end
  end

  def birthday(_other), do: {:error, @bad_birthday}

  @doc """
  The local date the `birthday` of a person next falls on or after `today`, today counting; nil
  with none. February 29 falls on the 28th in a year with no 29th.
  """
  @spec next_birthday(String.t() | nil, Date.t()) :: Date.t() | nil
  def next_birthday(nil, _today), do: nil

  def next_birthday(birthday, %Date{year: year} = today) do
    [month, day] = birthday |> String.slice(-5, 5) |> String.split("-") |> Enum.map(&String.to_integer/1)

    date = on_year(year, month, day)
    if Date.compare(date, today) == :lt, do: on_year(year + 1, month, day), else: date
  end

  @doc "A name as it is kept: trimmed, at most #{@max_name} characters; nil when it is none."
  @spec clean(term()) :: String.t() | nil
  def clean(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.slice(0, @max_name)
    |> case do
      "" -> nil
      name -> name
    end
  end

  def clean(_none), do: nil

  @doc """
  Start the pile `name` for `via` at `now`, with `rhythm` (`every`, `next_at`, either or both; `kind`,
  one of `agenda` (the default), `person` or `door`; and a person's `birthday`). A rhythm whose time
  has passed starts from its next one.
  """
  @spec create(String.t(), String.t(), map(), DateTime.t()) :: {:ok, t()} | {:error, String.t()}
  def create(via, name, rhythm, now) do
    attrs =
      [via: via, name: name] ++ Map.to_list(Map.take(rhythm, [:kind, :birthday])) ++ timing(%__MODULE__{}, rhythm, now)

    case Repo.insert(changeset(%__MODULE__{}, attrs), on_conflict: :nothing) do
      {:ok, %__MODULE__{id: nil, kind: kind}} -> {:error, taken(kind, name)}
      {:ok, agenda} -> {:ok, agenda}
      {:error, changeset} -> {:error, invalid(changeset)}
    end
  end

  @doc """
  Change `agenda` as the operator says: `changes` may hold `name`, `every` (nil stops the repeat),
  `next_at` (nil clears it) and `birthday` (nil clears it). A time that has passed on a repeat becomes
  its next one.
  """
  @spec edit(t(), map(), DateTime.t()) :: {:ok, t()} | {:error, String.t()}
  def edit(%__MODULE__{via: via, id: id, kind: kind} = agenda, changes, now) do
    name = Map.get(changes, :name, agenda.name)

    case named(via, name, kind) do
      %__MODULE__{id: other} when other != id ->
        {:error, taken(kind, name)}

      _free ->
        attrs = [name: name] ++ Map.to_list(Map.take(changes, [:birthday])) ++ timing(agenda, changes, now)

        agenda
        |> changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, agenda} -> {:ok, agenda}
          {:error, changeset} -> {:error, invalid(changeset)}
        end
    end
  end

  @doc "Delete `agenda` and the notes on its pile, at `now`."
  @spec delete(t(), DateTime.t()) :: :ok
  def delete(%__MODULE__{id: id} = agenda, now) do
    Jot.drop_agenda(id, now)
    Repo.delete!(agenda)
    :ok
  end

  @doc "Put the kept jot `jot` on the pile of `agenda` as the note `text`, at `now`: the note."
  @spec note(t(), Jot.t(), String.t(), DateTime.t()) :: Jot.t()
  def note(%__MODULE__{id: id}, %Jot{} = jot, text, now),
    do: Jot.file(jot, %{kind: "note", text: text, due_at: nil, agenda: id}, now)

  @doc "Archive the pile of `agenda` at `now`: its notes are kept, done. How many there were."
  @spec clear(t(), DateTime.t()) :: non_neg_integer()
  def clear(%__MODULE__{id: id}, now), do: Jot.archive_agenda(id, now)

  @doc "The agendas from `via` whose time is within the lead before it at `now` and that were not told for it yet."
  @spec due(String.t(), DateTime.t()) :: [t()]
  def due(via, now) do
    for %__MODULE__{next_at: %DateTime{} = at} = agenda <- all(via),
        DateTime.after?(at, now),
        DateTime.diff(at, now) <= @lead_min * 60,
        agenda.told_for != at,
        do: agenda
  end

  @doc "Record that `agenda` was told for its time at `now`: not told again for it."
  @spec told(t(), DateTime.t()) :: t()
  def told(%__MODULE__{next_at: at} = agenda, now),
    do: agenda |> Ecto.Changeset.change(told_for: at, told_at: DateTime.truncate(now, :second)) |> Repo.update!()

  @doc """
  Move on the agendas from `via` whose time went by an hour ago: a repeat to its next time after
  `now`, a one-off to none.
  """
  @spec advance(String.t(), DateTime.t()) :: :ok
  def advance(via, now) do
    gone = DateTime.add(now, -@linger_min * 60)

    for %__MODULE__{next_at: %DateTime{} = at} = agenda <- all(via), not DateTime.after?(at, gone) do
      next = if agenda.every, do: Clock.next(at, agenda.every, now, agenda.every_day)
      agenda |> Ecto.Changeset.change(next_at: next) |> Repo.update!()
    end

    :ok
  end

  @doc "The agendas from `via` told since `since`."
  @spec told_since(String.t(), DateTime.t()) :: [t()]
  def told_since(via, since),
    do: Repo.all(from(a in __MODULE__, where: a.via == ^via and a.told_at >= ^since, order_by: a.told_at))

  @doc "What the home says ahead of the occasion: `Retro in 15 — 3 things: a; b; c`. The pile is `notes`."
  @spec say_told(t(), [Jot.t()]) :: String.t()
  def say_told(%__MODULE__{} = agenda, notes),
    do: "#{upcase(agenda.name)} in #{@lead_min} — #{things(length(notes))}: #{Enum.map_join(notes, "; ", & &1.text)}"

  @doc "The reading of a note filed on the pile, said back: `On the retro pile (3).`"
  @spec say_pile(t(), non_neg_integer()) :: String.t()
  def say_pile(%__MODULE__{name: name}, count), do: "On the #{name} pile (#{count})."

  @doc "The pile `notes` of `agenda` as an answer to what is on it."
  @spec say_list(t(), [Jot.t()]) :: String.t()
  def say_list(%__MODULE__{name: name}, []), do: "Nothing on the #{name} pile."

  def say_list(%__MODULE__{name: name}, notes),
    do: Enum.join(["On the #{name} pile (#{length(notes)}):" | Enum.map(notes, &"• #{&1.text}")], "\n")

  @doc "The rhythm of `agenda` as the helper says it."
  @spec say_rhythm(t()) :: String.t()
  def say_rhythm(%__MODULE__{every: nil, next_at: nil, name: name}),
    do: "#{name} has no rhythm: bring it up when you want."

  def say_rhythm(%__MODULE__{every: nil, next_at: at, name: name}), do: "#{name} is #{Clock.say(at)}."
  def say_rhythm(%__MODULE__{every: every, next_at: nil, name: name}), do: "#{name} is every #{Clock.say_every(every)}."

  def say_rhythm(%__MODULE__{every: every, next_at: at, name: name}),
    do: "#{name} is every #{Clock.say_every(every)}, next #{Clock.say(at)}."

  defp changeset(agenda, attrs) do
    agenda
    |> Ecto.Changeset.change(attrs)
    |> Ecto.Changeset.validate_inclusion(:kind, @kinds, message: "kind must be agenda, person or door")
    |> Ecto.Changeset.validate_change(:birthday, fn :birthday, birthday ->
      case birthday(birthday) do
        {:ok, _kept} -> []
        {:error, why} -> [birthday: why]
      end
    end)
  end

  defp invalid(%Ecto.Changeset{errors: [{_field, {message, _meta}} | _]}), do: message

  defp taken("person", name), do: "there is already a person called #{name}"
  defp taken(_kind, name), do: "there is already an agenda called #{name}"

  defp things(1), do: "1 thing"
  defp things(count), do: "#{count} things"

  defp upcase(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest
  defp upcase(name), do: name

  defp timing(agenda, changes, now) do
    every = Map.get(changes, :every, agenda.every)
    at = Map.get(changes, :next_at, agenda.next_at)
    given? = Map.has_key?(changes, :every) or Map.has_key?(changes, :next_at)
    anchor = if given?, do: Jot.anchor(every, at), else: agenda.every_day
    next = if is_binary(every) and is_struct(at, DateTime), do: Clock.forward(at, every, now, anchor), else: at
    [every: every, every_day: anchor, next_at: next]
  end

  defp on_year(year, month, day) do
    case Date.new(year, month, day) do
      {:ok, date} -> date
      {:error, _no_29th} -> Date.new!(year, month, 28)
    end
  end
end
