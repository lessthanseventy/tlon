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
  in an hour, tomorrow, and delete under them. One left unanswered is said again, after 30 minutes and then at doubling
  gaps up to four hours, never between 22:00 and 08:00, six times in all. "done" typed in the chat
  is the reminder said last. A reminder that repeats is put off to its next time when done, and
  moves on to it by itself when it was never answered. What the home organizes by itself
  (`Server.Home.Organize`: a project's next step, waiting-ons, the weekly review at `home_review_on`
  and the offer of a smaller start after the daily list) is said in the same chat with its choices under it, and
  is answered by a tap or, for a project's next step, by typing it. "What now" is answered with one
  open thing and Done, Something else, Not today and Delete under it (`Server.Home.Now`). "Delete the
  milk" typed is the same as the button. Off unless `TLON_START_HOME_INBOX=1` (`:start_home_inbox`), which the service alone
  sets: a second node polling the same bot would take the operator's messages from it. With no token
  on the machine it does not start.
  """
  use GenServer

  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Organize
  alias Server.Home.Reader
  alias Server.Home.Slot
  alias Server.Jot

  require Logger

  @retry_ms 5_000
  @tick_ms 30_000
  @nudges 6
  @kept ["reminder", "todo", "note", "project", "waiting"]
  @done ["done", "did it", "did that"]

  @doc "Offer the smaller start `start` for the to-do `id` in the chat, once the model has written it."
  @spec shrink_offered(integer(), String.t(), DateTime.t()) :: :ok
  def shrink_offered(id, start, now) do
    if GenServer.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:shrink, id, start, now})
    :ok
  end

  @callback_limit 64

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
  under it. One whose message did not go out is said at the next poll. With no chat (`""`) it is
  only recorded as told, which is what the desktop raises (`Server.Home.told/1`).
  """
  @spec nudge(String.t(), String.t(), (String.t(), String.t(), keyword() -> term()), DateTime.t()) :: :ok
  def nudge(via, chat, say, now) do
    for jot <- Jot.due(via, now),
        jot = current(jot, now),
        turn?(jot, now),
        chat == "" or say.(chat, "reminder: #{jot.text}", choices: choices(jot)) == :ok do
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
    {coming, open} = Home.board(via, now)
    projects = Home.projects(via)

    parts =
      [
        section("Still open:", open, &"• #{Home.label(&1, projects)}"),
        section("Coming up:", Enum.take(coming, 8), &"• #{Clock.say(&1.due_at)}: #{&1.text}")
      ]

    case Enum.reject(parts, &is_nil/1) do
      [] -> nil
      parts -> {Enum.join(parts, "\n\n"), choices: for(jot <- Enum.take(open, 8), do: [tick(jot)])}
    end
  end

  @doc """
  The daily list: when a day's slot at `at` (`"17:30"`, local; `""` is never) has come round and was
  not said (`Server.Home.Clock.due/4`), what is open is said in `chat`, with an offer of a smaller
  start for a to-do that has sat (`Server.Home.Organize.shrink/2`); with no chat the offer is still
  put, for the desktop. Only in waking hours: a slot that went by asleep, or with the node down, is
  said at the first waking moment after it, once. `listed` is the date of the last slot said (a list
  said this morning for last night's 22:30 is last night's date), `:boot` when none is kept under the
  list's present time (`Server.Home.Clock.resume/2`), which counts the newest slot as said; the
  date of the slot now said is answered. `slots/7` keeps it (`Server.Home.Slot`) across a restart.
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
  def daily(_via, _chat, _say, now, at, :boot),
    do: Clock.slot(now, at) || now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(-1)

  def daily(via, chat, say, now, at, %Date{} = listed) do
    case Clock.due(listed, now, at) do
      {:say, slot} ->
        said(via, chat, say, now)
        slot

      :wait ->
        listed
    end
  end

  @doc """
  Keep what the operator said (`text`, delivery `id` of `via`) at `now` and read it, as a text in the
  chat is: `{reply, say opts}`, or `:seen` when `via` already delivered `id`.
  """
  @spec keep(String.t(), integer(), String.t(), DateTime.t()) :: {String.t(), keyword()} | :seen
  def keep(via, id, text, now) do
    case if(String.downcase(String.trim(text)) in @done, do: Jot.last_nudged(via)) do
      %Jot{} = jot -> finished(jot, now)
      nil -> with {:ok, jot} <- Jot.take(via, id, text), do: filed(jot, via, now)
    end
  end

  @doc ~s(Put the open thing `jot` off, `until` an `"hour"` from `now` or `"tomorrow"` at 09:00 local: the jot.)
  @spec later(Jot.t(), String.t(), DateTime.t()) :: Jot.t()
  def later(jot, "hour", now), do: Jot.put_off(jot, DateTime.add(now, 3600), now)

  def later(jot, "tomorrow", now) do
    morning = now |> Clock.local() |> NaiveDateTime.to_date() |> Date.add(1) |> NaiveDateTime.new!(~T[09:00:00])
    Jot.put_off(jot, Clock.utc(morning), now)
  end

  @doc """
  Say the question put on the project `id` (a next step that took a model call) in the paired chat,
  if the inbox is running with a messenger. The desktop raises it from the row either way.
  """
  @spec asked_now(integer()) :: :ok
  def asked_now(id) do
    if GenServer.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:asked, id})
    :ok
  end

  @doc "Say the next-step question on project `id` from `via` in `chat` through `say`; nothing when there is none or no chat."
  @spec tell_ask(String.t(), String.t(), (String.t(), String.t(), keyword() -> term()), integer()) :: :ok
  def tell_ask(via, chat, say, id) do
    with true <- chat != "",
         %Jot{ask: "next"} = project <- Jot.asked(via, id) do
      {text, opts} = Organize.prompt_reply(project)
      say.(chat, text, opts)
    end

    :ok
  end

  @doc """
  The data of the "Something else" button for a pick made with `minutes` (0 for none) that has left
  out `ids`, newest first: as many of the newest as fit in Telegram's #{@callback_limit} bytes.
  """
  @spec else_data(non_neg_integer(), [integer()]) :: String.t()
  def else_data(minutes, ids) do
    head = "n:#{minutes}:"

    kept =
      Enum.reduce_while(ids, [], fn id, kept ->
        fits = kept ++ [id]
        if byte_size(head <> Enum.join(fits, "-")) <= @callback_limit, do: {:cont, fits}, else: {:halt, kept}
      end)

    head <> Enum.join(kept, "-")
  end

  @impl true
  def init(opts) do
    messenger = Keyword.get(opts, :messenger, Application.get_env(:server, :home_messenger, Server.Home.Telegram))

    if messenger.token() do
      send(self(), :poll)

      {:ok, Map.merge(%{messenger: messenger, offset: (Jot.cursor(messenger.name()) || -1) + 1}, kept())}
    else
      send(self(), :tick)
      {:ok, Map.merge(%{messenger: messenger}, kept())}
    end
  end

  # no messenger: the reminders are still told on time, to the desktop
  @impl true
  def handle_info(:tick, %{messenger: messenger} = state) do
    now = DateTime.utc_now()
    guarded(:ok, fn -> nudge(messenger.name(), "", nil, now) end)
    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, tend(state, "", nil, now)}
  end

  def handle_info(:poll, %{messenger: messenger, offset: offset} = state) do
    chat = Server.OperatorConfig.setting("home_chat")
    now = DateTime.utc_now()
    guarded(:ok, fn -> nudge(messenger.name(), chat, &messenger.say/3, now) end)
    state = tend(state, chat, &messenger.say/3, now)

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

  @impl true
  def handle_cast({:asked, id}, %{messenger: messenger} = state) do
    if Map.has_key?(state, :offset) do
      guarded(:ok, fn ->
        tell_ask(messenger.name(), Server.OperatorConfig.setting("home_chat"), &messenger.say/3, id)
      end)
    end

    {:noreply, state}
  end

  def handle_cast({:shrink, id, start, now}, %{messenger: messenger} = state) do
    guarded(:ok, fn ->
      {chat, say} =
        if Map.has_key?(state, :offset),
          do: {Server.OperatorConfig.setting("home_chat"), &messenger.say/3},
          else: {"", nil}

      Organize.offer_shrink(messenger.name(), id, start, chat, say, now)
    end)

    {:noreply, state}
  end

  # one odd row must not take the inbox, and so the reminders and the chat, down: each piece of upkeep
  # fails alone and is tried again at the next poll
  defp tend(%{messenger: messenger} = state, chat, say, now) do
    via = messenger.name()
    guarded(:ok, fn -> Organize.waiting(via, chat, say, now) end)

    slots(
      state,
      via,
      chat,
      say,
      now,
      Server.OperatorConfig.setting("home_list_at"),
      Server.OperatorConfig.setting("home_review_on")
    )
  end

  @doc "The slots kept from before the inbox started: `%{listed, reviewed}`, each `{date, setting}` or nil."
  @spec kept() :: %{listed: {Date.t(), String.t()} | nil, reviewed: {Date.t(), String.t()} | nil}
  def kept, do: %{listed: Slot.get("daily"), reviewed: Slot.get("weekly")}

  @doc """
  Say what is due on a schedule at `now`, with the list at `at` and the review on `on`: the daily
  list and the weekly review, each trusted only under the setting its last slot was kept for. The
  slot said is written (`Server.Home.Slot`) and the state the inbox carries is answered.
  """
  @spec slots(
          map(),
          String.t(),
          String.t(),
          (String.t(), String.t(), keyword() -> term()) | nil,
          DateTime.t(),
          String.t(),
          String.t()
        ) ::
          map()
  def slots(state, via, chat, say, now, at, on) do
    listed = slot("daily", state.listed, at, &daily(via, chat, say, now, at, &1))
    reviewed = slot("weekly", state.reviewed, at <> "|" <> on, &Organize.weekly(via, chat, say, now, on, at, &1))
    %{state | listed: listed, reviewed: reviewed}
  end

  defp slot(name, kept, setting, run) do
    last = Clock.resume(kept, setting)
    new = guarded(last, fn -> run.(last) end)
    if new != last and new != :boot, do: Slot.put(name, new, setting)
    {new, setting}
  end

  defp guarded(default, fun) do
    fun.()
  rescue
    error ->
      Logger.error("home inbox: upkeep failed: #{Exception.message(error)}")
      default
  end

  defp speak(chat, say, {text, opts}, prefix \\ "") do
    {later, opts} = Keyword.pop(opts, :then, [])
    say.(chat, prefix <> text, opts)
    Enum.each(later, fn {text, opts} -> say.(chat, text, opts) end)
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

    {text, opts} = tap(tap, via, now)
    say.(chat, text, [replace: ref] ++ opts)
  end

  defp take(%{chat: chat, text: "/" <> _command}, _via, chat, say),
    do: say.(chat, "Text me anything and I'll keep it.", [])

  defp take(%{chat: chat, text: text, id: id}, via, chat, say) when is_binary(text) do
    with {_text, _opts} = reply <- keep(via, id, text, DateTime.utc_now()), do: speak(chat, say, reply)
  end

  defp take(%{chat: chat, voice: file, id: id}, via, chat, say) do
    case Application.get_env(:server, :home_ear, &Server.Home.Ear.hear/1).(file) do
      {:ok, heard} ->
        with {:ok, jot} <- Jot.take(via, id, heard) do
          speak(chat, say, filed(jot, via, DateTime.utc_now()), "heard: “#{heard}”\n")
        end

      {:error, why} ->
        Logger.warning("home inbox: a voice note was not heard: #{inspect(why)}")
        say.(chat, "I couldn't make that one out: type it and I'll keep it.", [])
    end
  end

  defp take(%{chat: chat}, _via, chat, say),
    do: say.(chat, "I can only keep text so far: type it and I'll keep it.", [])

  defp take(_update, _via, _chat, _say), do: :ok

  defp tap("a:" <> answer, via, now) do
    with [id, choice] <- String.split(answer, ":"),
         {id, ""} <- Integer.parse(id),
         {:ok, reply} <- Organize.answer(via, id, choice, nil, now) do
      reply
    else
      _ -> {"That one is already answered.", []}
    end
  end

  defp tap("n:" <> else_, _via, now) do
    with [minutes, skipped] <- String.split(else_, ":"),
         {minutes, ""} <- Integer.parse(minutes),
         skip when skip != [] <- for(id <- String.split(skipped, "-"), {id, ""} <- [Integer.parse(id)], do: id) do
      now(skip, minutes, now)
    else
      _ -> now([], 0, now)
    end
  end

  defp tap(tap, via, now) do
    with [what, id] <- String.split(tap, ":"),
         {id, ""} <- Integer.parse(id),
         %Jot{} = jot <- Jot.open(via, id) do
      tapped(what, jot, via, now)
    else
      _ -> gone(tap, via, now)
    end
  end

  defp now(skip, minutes, now) do
    asked = if minutes > 0, do: minutes
    %{pick: pick, say: say} = Home.now(skip, asked, now)

    case pick do
      nil ->
        {say, []}

      %{id: id} ->
        {say,
         choices: [
           [
             {"Done", "done:#{id}"},
             {"Something else", else_data(minutes, [id | skip])},
             {"Not today", "a:#{id}:nottoday"}
           ],
           [{"Delete", "drop:#{id}"}]
         ]}
    end
  end

  defp tapped("done", jot, _via, now), do: finished(jot, now)
  defp tapped("drop", jot, _via, now), do: deleted(jot, now)
  defp tapped(until, jot, _via, now) when until in ["hour", "tomorrow"], do: {Reader.say(later(jot, until, now)), []}

  defp tapped("tick", jot, via, now) do
    Jot.done(jot, now)
    join(listed(via, now), Organize.advance(jot, now))
  end

  defp gone("tick:" <> _id, via, now), do: listed(via, now)
  defp gone(_tap, _via, _now), do: {"That one is already done.", []}

  defp closed(jot, now) do
    case Jot.done(jot, now) do
      %Jot{done_at: nil, due_at: next} -> "done: #{jot.text}. Next: #{Clock.say(next)}"
      _done -> "done: #{jot.text}"
    end
  end

  defp finished(jot, now), do: join({closed(jot, now), []}, Organize.advance(jot, now))

  defp deleted(jot, now) do
    {line, more} = dropping(jot, now)
    join({line, []}, more)
  end

  defp dropping(jot, now) do
    {gone, more} = Organize.delete(jot, now)
    {"deleted: #{gone.text}", more}
  end

  defp join(base, nil), do: base

  defp join({text, opts}, {more, more_opts}),
    do: {text <> "\n\n" <> more, Keyword.update(opts, :choices, more_opts[:choices], &(&1 ++ more_opts[:choices]))}

  defp listed(via, now), do: digest(via, now) || {"Nothing open.", []}

  defp filed(jot, via, now) do
    context = %{
      previous: Jot.last_filed(via),
      open: Jot.opens(via),
      notes: Jot.notes(via, 60),
      projects: Jot.projects(via),
      someday: Jot.somedays(via)
    }

    reader = Application.get_env(:server, :home_reader, &Reader.read/2)

    case reader.(jot.body, context) do
      {:ok, %{amends: true, kind: kind} = reading} when context.previous != nil and kind in @kept ->
        reply = Organize.file(context.previous, reading, now)
        Jot.file(jot, %{kind: "amend", text: nil, due_at: nil}, now)
        {"changed: " <> reply, []}

      {:ok, %{kind: kind} = reading} when kind in ["done", "delete", "list", "answer", "now", "someday"] ->
        Jot.file(jot, %{kind: "talk", text: nil, due_at: nil}, now)
        asked(reading, via, now)

      {:ok, reading} ->
        {Organize.file(jot, reading, now), []}

      :error ->
        {"got it", []}
    end
  end

  defp asked(%{kind: "answer", text: text}, _via, _now), do: {text, []}
  defp asked(%{kind: "list"}, via, now), do: listed(via, now)
  defp asked(%{kind: "now"} = reading, _via, now), do: now([], Map.get(reading, :minutes, 0), now)

  defp asked(%{kind: "someday"}, via, _now) do
    case Jot.somedays(via) do
      [] -> {"Nothing on someday.", []}
      jots -> {Enum.join(["On someday:" | Enum.map(jots, &"• #{&1.text}")], "\n"), []}
    end
  end

  defp asked(%{kind: "done", ids: ids}, via, now),
    do: told(ids, via, now, &Jot.open/2, &{closed(&1, &2), Organize.advance(&1, &2)})

  defp asked(%{kind: "delete", ids: ids}, via, now), do: told(ids, via, now, &Jot.live/2, &dropping/2)

  defp told(ids, via, now, find, close) do
    case for id <- ids, jot = find.(via, id), do: close.(jot, now) do
      [] ->
        {text, opts} = listed(via, now)
        {"I couldn't tell which one you meant.\n\n" <> text, opts}

      done ->
        asks = for {_closed, {_text, _opts} = ask} <- done, do: ask
        {Enum.map_join(done, "\n", &elem(&1, 0)), if(asks == [], do: [], else: [then: asks])}
    end
  end

  defp section(_title, [], _line), do: nil
  defp section(title, jots, line), do: Enum.join([title | Enum.map(jots, line)], "\n")

  defp tick(jot), do: {"✓ " <> String.slice(to_string(jot.text), 0, 30), "tick:#{jot.id}"}

  # a reminder that repeats and was never answered stands at its newest time that has come
  defp current(%Jot{every: nil} = jot, _now), do: jot

  defp current(%Jot{every: every, due_at: due} = jot, now) do
    case Clock.latest(due, every, now) do
      ^due -> jot
      latest -> Jot.roll(jot, latest)
    end
  end

  defp choices(jot),
    do: [
      [{"Done", "done:#{jot.id}"}, {"In an hour", "hour:#{jot.id}"}, {"Tomorrow", "tomorrow:#{jot.id}"}],
      [{"Delete", "drop:#{jot.id}"}]
    ]

  defp turn?(%Jot{nudges: 0}, _now), do: true
  defp turn?(%Jot{nudges: n}, _now) when n >= @nudges, do: false

  defp turn?(%Jot{nudges: n, nudged_at: last}, now),
    do: DateTime.diff(now, last, :minute) >= min(30 * 2 ** (n - 1), 240) and Clock.awake?(now)

  defp said(via, chat, say, now) do
    Organize.shrink(via, now)

    with true <- chat != "",
         {text, opts} <- digest(via, now) do
      say.(chat, "Before you clock out:\n\n" <> text, opts)
    end

    :ok
  end
end
