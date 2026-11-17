defmodule Server.Home.Inbox do
  @moduledoc """
  The home's inbox: what the operator texts a messenger bot from their phone is kept as a
  `Server.Jot` and answered, so a thought is written down the moment it is had. One chat is the
  operator's, the `home_chat` setting; until one is set a chat that writes is told its own id and
  nothing is kept, and once one is set every other chat is ignored. The messenger is a module
  (`:home_messenger`, default `Server.Home.Telegram`) answering `name/0`, `token/0`, `updates/1`
  and `say/2`. A message that starts with `/` is the messenger's own command (`/start`), greeted and
  never kept. A voice note is heard on this machine (`:home_ear`, default `Server.Home.Ear.hear/1`)
  and its words are the jot, said back as heard. A kept jot is read (`:home_reader`, default `Server.Home.Reader.read/2`) and the reading
  said back, so a wrong one shows at once; a message that corrects the jot before it changes that
  jot's reading; with no reading the answer is "got it" and the jot stays raw. A message can also
  ask the helper for something, and is then nothing to keep: that things are done, what is open
  (`digest/2`, each open thing with a button that ticks it off), or a question its notes answer.
  Once a day, at the `home_list_at` setting, what is open is said unasked (`daily/6`). Before each poll the
  reminders that have come due are said in the chat (`nudge/4`) with three choices under each: done,
  in an hour, tomorrow. One left unanswered is said again, after 30 minutes and then at doubling
  gaps up to four hours, never between 22:00 and 08:00, six times in all. "done" typed in the chat
  is the reminder said last. A reminder that repeats is put off to its next time when done, and
  moves on to it by itself when it was never answered. Off unless `TLON_START_HOME_INBOX=1` (`:start_home_inbox`), which the service alone
  sets: a second node polling the same bot would take the operator's messages from it. With no token
  on the machine it does not start.
  """
  use GenServer

  alias Server.Home.Clock
  alias Server.Home.Reader
  alias Server.Jot

  require Logger

  @retry_ms 5_000
  @nudges 6
  @done ["done", "did it", "did that"]

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Take `updates` (`%{id, chat, text}`, as the messenger gives them) from `via`: a text from `chat`
  is kept and answered through `say` (`chat, text, opts`, as the messenger's `say/3`), once however
  often it is delivered; a tap on a reminder's choice is carried out. The offset the next poll starts
  at, nil when there were none.
  """
  @spec hear([map()], String.t(), String.t(), (String.t(), String.t(), keyword() -> term())) :: integer() | nil
  def hear([], _via, _chat, _say), do: nil

  def hear(updates, via, chat, say) do
    Enum.each(updates, &take(&1, via, chat, say))
    List.last(updates).id + 1
  end

  @doc """
  Say in `chat` each reminder from `via` that is due at `now` and whose turn it is, with its choices
  under it. One whose message did not go out is said at the next poll.
  """
  @spec nudge(String.t(), String.t(), (String.t(), String.t(), keyword() -> term()), DateTime.t()) :: :ok
  def nudge(_via, "", _say, _now), do: :ok

  def nudge(via, chat, say, now) do
    for jot <- Jot.due(via, now),
        jot = current(jot, now),
        turn?(jot, now),
        say.(chat, "reminder: #{jot.text}", choices: [choices(jot)]) == :ok do
      Jot.nudged(jot, now)
    end

    :ok
  end

  @doc """
  What is open from `via` at `now`, as text and the `say` options that put a button under it for
  each thing that can be ticked off: the to-dos and the reminders whose time has passed, then the
  reminders to come. nil when nothing is open.
  """
  @spec digest(String.t(), DateTime.t()) :: {String.t(), keyword()} | nil
  def digest(via, now) do
    {coming, open} =
      via |> Jot.opens() |> Enum.split_with(&(&1.kind == "reminder" and DateTime.after?(&1.due_at, now)))

    parts =
      [
        section("Still open:", open, &"• #{&1.text}"),
        section("Coming up:", Enum.take(coming, 8), &"• #{Clock.say(&1.due_at)}: #{&1.text}")
      ]

    case Enum.reject(parts, &is_nil/1) do
      [] -> nil
      parts -> {Enum.join(parts, "\n\n"), choices: for(jot <- Enum.take(open, 8), do: [tick(jot)])}
    end
  end

  @doc """
  The daily list: once `now` is past `at` (`"17:30"`, local; `""` is never) on a day it has not been
  said, what is open is said in `chat`. `listed` is the day it was last said, `:boot` when the inbox
  has just started; the day it now stands at is answered.
  """
  @spec daily(
          String.t(),
          String.t(),
          (String.t(), String.t(), keyword() -> term()),
          DateTime.t(),
          String.t(),
          Date.t() | :boot
        ) ::
          Date.t()
  def daily(via, chat, say, now, at, listed) do
    local = Clock.local(now)
    today = NaiveDateTime.to_date(local)
    past? = past?(NaiveDateTime.to_time(local), Time.from_iso8601(at <> ":00"))

    cond do
      listed == :boot and past? -> today
      listed == :boot -> Date.add(today, -1)
      not past? or listed == today or chat == "" -> listed
      true -> said(digest(via, now), chat, say, today)
    end
  end

  @impl true
  def init(opts) do
    messenger = Keyword.get(opts, :messenger, Application.get_env(:server, :home_messenger, Server.Home.Telegram))

    if messenger.token() do
      send(self(), :poll)
      {:ok, %{messenger: messenger, offset: (Jot.cursor(messenger.name()) || -1) + 1, listed: :boot}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:poll, %{messenger: messenger, offset: offset} = state) do
    chat = Server.OperatorConfig.setting("home_chat")
    now = DateTime.utc_now()
    nudge(messenger.name(), chat, &messenger.say/3, now)
    at = Server.OperatorConfig.setting("home_list_at")
    state = %{state | listed: daily(messenger.name(), chat, &messenger.say/3, now, at, state.listed)}

    case messenger.updates(offset) do
      {:ok, updates} ->
        next = hear(updates, messenger.name(), chat, &messenger.say/3)
        send(self(), :poll)
        {:noreply, %{state | offset: next || offset}}

      {:error, why} ->
        Logger.warning("home inbox: #{messenger.name()} did not answer: #{inspect(why)}")
        Process.send_after(self(), :poll, @retry_ms)
        {:noreply, state}
    end
  end

  defp take(%{chat: nil}, _via, _chat, _say), do: :ok

  defp take(%{chat: from}, _via, "", say) do
    say.(
      from,
      "This helper is not paired with a chat yet. This chat's id is #{from}: set `home_chat` to it in tlon's settings.",
      []
    )
  end

  defp take(%{chat: chat, tap: tap, ref: ref}, via, chat, say) do
    now = DateTime.utc_now()

    {text, opts} =
      with [what, id] <- String.split(tap, ":"),
           {id, ""} <- Integer.parse(id),
           %Jot{} = jot <- Jot.open(via, id) do
        tapped(what, jot, via, now)
      else
        _ -> gone(tap, via, now)
      end

    say.(chat, text, [replace: ref] ++ opts)
  end

  defp take(%{chat: chat, text: "/" <> _command}, _via, chat, say),
    do: say.(chat, "Text me anything and I'll keep it.", [])

  defp take(%{chat: chat, text: text, id: id}, via, chat, say) when is_binary(text) do
    now = DateTime.utc_now()

    case if(String.downcase(String.trim(text)) in @done, do: Jot.last_nudged(via)) do
      %Jot{} = jot ->
        say.(chat, closed(jot, now), [])

      nil ->
        with {:ok, jot} <- Jot.take(via, id, text) do
          {text, opts} = filed(jot, via, now)
          say.(chat, text, opts)
        end
    end
  end

  defp take(%{chat: chat, voice: file, id: id}, via, chat, say) do
    case Application.get_env(:server, :home_ear, &Server.Home.Ear.hear/1).(file) do
      {:ok, heard} ->
        with {:ok, jot} <- Jot.take(via, id, heard) do
          {text, opts} = filed(jot, via, DateTime.utc_now())
          say.(chat, "heard: “#{heard}”\n" <> text, opts)
        end

      {:error, why} ->
        Logger.warning("home inbox: a voice note was not heard: #{inspect(why)}")
        say.(chat, "I couldn't make that one out: type it and I'll keep it.", [])
    end
  end

  defp take(%{chat: chat}, _via, chat, say),
    do: say.(chat, "I can only keep text so far: type it and I'll keep it.", [])

  defp take(_update, _via, _chat, _say), do: :ok

  defp tapped("done", jot, _via, now), do: {closed(jot, now), []}
  defp tapped("hour", jot, _via, now), do: {Reader.say(Jot.put_off(jot, DateTime.add(now, 3600))), []}

  defp tapped("tomorrow", jot, _via, now) do
    morning = now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(1) |> NaiveDateTime.new!(~T[09:00:00])
    {Reader.say(Jot.put_off(jot, Clock.utc(morning))), []}
  end

  defp tapped("tick", jot, via, now) do
    Jot.done(jot, now)
    listed(via, now)
  end

  defp gone("tick:" <> _id, via, now), do: listed(via, now)
  defp gone(_tap, _via, _now), do: {"That one is already done.", []}

  defp closed(jot, now) do
    case Jot.done(jot, now) do
      %Jot{done_at: nil, due_at: next} -> "done: #{jot.text}. Next: #{Clock.say(next)}"
      _done -> "done: #{jot.text}"
    end
  end

  defp listed(via, now), do: digest(via, now) || {"Nothing open.", []}

  defp filed(jot, via, now) do
    context = %{previous: Jot.last_filed(via), open: Jot.opens(via), notes: Jot.notes(via, 60)}
    reader = Application.get_env(:server, :home_reader, &Reader.read/2)

    case reader.(jot.body, context) do
      {:ok, %{amends: true} = reading} when context.previous != nil ->
        Jot.file(context.previous, reading)
        Jot.file(jot, %{kind: "amend", text: nil, due_at: nil})
        {"changed: " <> Reader.say(reading), []}

      {:ok, %{kind: kind} = reading} when kind in ["done", "list", "answer"] ->
        Jot.file(jot, %{kind: "talk", text: nil, due_at: nil})
        asked(reading, via, now)

      {:ok, reading} ->
        Jot.file(jot, reading)
        {Reader.say(reading), []}

      :error ->
        {"got it", []}
    end
  end

  defp asked(%{kind: "answer", text: text}, _via, _now), do: {text, []}
  defp asked(%{kind: "list"}, via, now), do: listed(via, now)

  defp asked(%{kind: "done", ids: ids}, via, now) do
    case for id <- ids, jot = Jot.open(via, id), do: closed(jot, now) do
      [] ->
        {text, opts} = listed(via, now)
        {"I couldn't tell which one you meant.\n\n" <> text, opts}

      closed ->
        {Enum.join(closed, "\n"), []}
    end
  end

  defp section(_title, [], _line), do: nil
  defp section(title, jots, line), do: Enum.join([title | Enum.map(jots, line)], "\n")

  defp tick(jot), do: {"✓ " <> String.slice(jot.text, 0, 30), "tick:#{jot.id}"}

  # a reminder that repeats and was never answered stands at its newest time that has come
  defp current(%Jot{every: nil} = jot, _now), do: jot

  defp current(%Jot{every: every, due_at: due} = jot, now) do
    case Clock.latest(due, every, now) do
      ^due -> jot
      latest -> Jot.put_off(jot, latest)
    end
  end

  defp choices(jot),
    do: [{"Done", "done:#{jot.id}"}, {"In an hour", "hour:#{jot.id}"}, {"Tomorrow", "tomorrow:#{jot.id}"}]

  defp turn?(%Jot{nudges: 0}, _now), do: true
  defp turn?(%Jot{nudges: n}, _now) when n >= @nudges, do: false

  defp turn?(%Jot{nudges: n, nudged_at: last}, now),
    do: DateTime.diff(now, last, :minute) >= min(30 * 2 ** (n - 1), 240) and Clock.local(now).hour in 8..21

  defp past?(time, {:ok, at}), do: Time.compare(time, at) != :lt
  defp past?(_time, _never), do: false

  defp said(nil, _chat, _say, today), do: today

  defp said({text, opts}, chat, say, today) do
    say.(chat, "Before you clock out:\n\n" <> text, opts)
    today
  end
end
