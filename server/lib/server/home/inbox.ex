defmodule Server.Home.Inbox do
  @moduledoc """
  The home's inbox: what the operator texts a messenger bot from their phone is kept as a
  `Server.Jot` and answered, so a thought is written down the moment it is had. One chat is the
  operator's, the `home_chat` setting; until one is set a chat that writes is told its own id and
  nothing is kept, and once one is set every other chat is ignored. The messenger is a module
  (`:home_messenger`, default `Server.Home.Telegram`) answering `name/0`, `token/0`, `updates/1`
  and `say/2`. A message that starts with `/` is the messenger's own command (`/start`), greeted and
  never kept. A kept jot is read (`:home_reader`, default `Server.Home.Reader.read/2`) and the reading
  said back, so a wrong one shows at once; a message that corrects the jot before it changes that
  jot's reading; with no reading the answer is "got it" and the jot stays raw. Before each poll the
  reminders that have come due are said in the chat (`nudge/4`) with three choices under each: done,
  in an hour, tomorrow. One left unanswered is said again, after 30 minutes and then at doubling
  gaps up to four hours, never between 22:00 and 08:00, six times in all. "done" typed in the chat
  is the reminder said last. Off unless `TLON_START_HOME_INBOX=1` (`:start_home_inbox`), which the service alone
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
    for jot <- Jot.due(via, now), turn?(jot, now), say.(chat, "reminder: #{jot.text}", choices: choices(jot)) == :ok do
      Jot.nudged(jot, now)
    end

    :ok
  end

  @impl true
  def init(opts) do
    messenger = Keyword.get(opts, :messenger, Application.get_env(:server, :home_messenger, Server.Home.Telegram))

    if messenger.token() do
      send(self(), :poll)
      {:ok, %{messenger: messenger, offset: (Jot.cursor(messenger.name()) || -1) + 1}}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:poll, %{messenger: messenger, offset: offset} = state) do
    chat = Server.OperatorConfig.setting("home_chat")
    nudge(messenger.name(), chat, &messenger.say/3, DateTime.utc_now())

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
    with [what, id] <- String.split(tap, ":"),
         {id, ""} <- Integer.parse(id),
         %Jot{} = jot <- Jot.open(via, id) do
      say.(chat, tapped(what, jot, DateTime.utc_now()), replace: ref)
    else
      _ -> say.(chat, "That one is already done.", replace: ref)
    end
  end

  defp take(%{chat: chat, text: "/" <> _command}, _via, chat, say),
    do: say.(chat, "Text me anything and I'll keep it.", [])

  defp take(%{chat: chat, text: text, id: id}, via, chat, say) when is_binary(text) do
    case if(String.downcase(String.trim(text)) in @done, do: Jot.last_nudged(via)) do
      %Jot{} = jot -> say.(chat, tapped("done", jot, DateTime.utc_now()), [])
      nil -> with {:ok, jot} <- Jot.take(via, id, text), do: say.(chat, filed(jot, Jot.last_filed(via)), [])
    end
  end

  defp take(%{chat: chat}, _via, chat, say),
    do: say.(chat, "I can only keep text so far: type it and I'll keep it.", [])

  defp take(_update, _via, _chat, _say), do: :ok

  defp tapped("done", jot, now) do
    Jot.done(jot, now)
    "done: #{jot.text}"
  end

  defp tapped("hour", jot, now), do: Reader.say(Jot.put_off(jot, DateTime.add(now, 3600)))

  defp tapped("tomorrow", jot, now) do
    morning = now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(1) |> NaiveDateTime.new!(~T[09:00:00])
    Reader.say(Jot.put_off(jot, Clock.utc(morning)))
  end

  defp filed(jot, previous) do
    reader = Application.get_env(:server, :home_reader, &Reader.read/2)

    case reader.(jot.body, previous) do
      {:ok, %{amends: true} = reading} when previous != nil ->
        Jot.file(previous, reading)
        Jot.file(jot, %{kind: "amend", text: nil, due_at: nil})
        "changed: " <> Reader.say(reading)

      {:ok, reading} ->
        Jot.file(jot, reading)
        Reader.say(reading)

      :error ->
        "got it"
    end
  end

  defp choices(jot),
    do: [{"Done", "done:#{jot.id}"}, {"In an hour", "hour:#{jot.id}"}, {"Tomorrow", "tomorrow:#{jot.id}"}]

  defp turn?(%Jot{nudges: 0}, _now), do: true
  defp turn?(%Jot{nudges: n}, _now) when n >= @nudges, do: false

  defp turn?(%Jot{nudges: n, nudged_at: last}, now),
    do: DateTime.diff(now, last, :minute) >= min(30 * 2 ** (n - 1), 240) and Clock.local(now).hour in 8..21
end
