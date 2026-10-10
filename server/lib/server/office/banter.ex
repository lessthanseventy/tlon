defmodule Server.Office.Banter do
  @moduledoc """
  The office's small talk: now and then a coworker says something — about their work, someone
  else's, the boss, the room, or just a joke — written by a cheap model in a drawn mood
  (`Server.Office.Writer`: Haiku or deepseek by day, the ollama models by night).

  Each line is one of several KINDS of remark (`kinds/0`), drawn by weight (`pick/2`); a kind's
  weight reads the moment, so one that has nothing to say about it (no one else working, nothing
  finished) is never drawn. The server picks the speaker and the kind; the model only writes it.

  Lazy on purpose: a line is only written while an office asks (`lines/1` from its poll), at most
  one per workspace every `@every_s` (sooner the wilder the dial: `Server.Office.Writer.every/2`), so
  a room nobody watches costs nothing. On by default: a node
  runs it unless `TLON_BANTER=0` (`:start_banter`), and the operator's settings file switches it off
  live (`"banter": false`, `Server.OperatorConfig.banter?/0`, flipped from the office's settings).
  A reply that does not parse is dropped.
  """
  use GenServer

  import Ecto.Query

  @every_s 120
  @keep_s 300
  @voice """
  You write ONE line of small talk for a coworker in a pixel-art office of AI coworkers, said out
  loud as they walk around. Under 80 characters. Dry, warm, a little absurd; in character for their
  role; no emoji, no hashtags, never cruel, never a list. Respond with ONLY a JSON object:
  {"line": "<what they say>"}
  """

  @chat_voice """
  You write a SHORT conversation between two coworkers in a pixel-art office of AI coworkers, said
  out loud in speech balloons as they pass each other. 2 to 4 turns, alternating, each under 80
  characters. Dry, warm, a little absurd; each in character for their role; a coworker is "they",
  never "he" or "she"; no emoji, never cruel. Respond with ONLY a JSON object:
  {"turns": [{"who": "<their name>", "line": "<what they say>"}, ...]}
  """
  @turn_s 5
  # a conversation the room asks for (`talk/4`): one per workspace this often, the same pair less often
  @talk_every_s 45
  @pair_every_s 300
  @situations %{
    "pingpong" => "are playing ping-pong against each other",
    "foosball" => "are playing foosball against each other",
    "pool" => "are playing a game of pool",
    "arcade" => "are taking turns at the arcade machine",
    "couch" => "are on the lounge couch watching the TV (a cellular automaton, or whatever is on)",
    "coffee" => "are waiting at the coffee machine",
    "cooler" => "have run into each other at the water cooler",
    "vending" => "are at the snack machine",
    "hall" => "pass each other in the hall, one on the way somewhere",
    "chat" => "stopped by each other's spot for a word"
  }

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  The workspace's recent lines, oldest first, as `%{agent, line, kind, at, delay}` (`at` in unix
  seconds; a chat's turns share an `at`, each to be said `delay` seconds after the first) —
  and, when the last one is stale, a new one is asked for in the background. `[]` where banter is off.
  """
  @spec lines(integer()) :: [map()]
  def lines(workspace_id) do
    if GenServer.whereis(__MODULE__) && Server.OperatorConfig.banter?(),
      do: GenServer.call(__MODULE__, {:lines, workspace_id}),
      else: []
  end

  @doc """
  The kinds of remark: `{name, weight, ask}`. `weight` reads the moment (`ctx`, `speaker`) and 0
  means "nothing to say"; `ask` is what the model is asked to say, from the same two.
  """
  def kinds do
    [
      {:own_work, fn _ctx, s -> if s.thread, do: 30, else: 0 end,
       fn _ctx, s ->
         "#{s.name} remarks on their OWN work: #{thread_line(s.thread)}\nIts latest messages:\n#{recent(s.thread)}"
       end},
      {:colleague, fn ctx, s -> if others(ctx, s) == [], do: 0, else: 20 end,
       fn ctx, s ->
         o = Enum.random(others(ctx, s))

         "#{s.name} remarks on what #{o.name} (#{o.archetype}) is doing: #{thread_line(o.thread)}\nIts latest messages:\n#{recent(o.thread)}"
       end},
      {:joke, fn _ctx, _s -> 25 end,
       fn _ctx, s ->
         "#{s.name} cracks a joke or a pun — programmer humour, office life, or about being a #{s.archetype}. It need not be about the work."
       end},
      {:room, fn _ctx, _s -> 12 end,
       fn _ctx, s ->
         "#{s.name} remarks on something in the office: " <>
           Enum.random([
             "Nina, the office cat, asleep somewhere inconvenient",
             "the lounge TV, showing a cellular automaton again",
             "the coffee machine",
             "the whiteboard full of worklines",
             "the filing cabinet of finished work",
             "the windows and the weather",
             "the boss's trophy"
           ])
       end},
      {:boss, fn ctx, _s -> if ctx.boss != [] or ctx.awaiting > 0, do: 8, else: 0 end,
       fn ctx, s ->
         "#{s.name} remarks on the boss (#{ctx.operator}) — their style, their requests, how they write#{if ctx.awaiting > 0, do: ", or the #{ctx.awaiting} thread(s) waiting on them", else: ""}. Affectionate.\nThe boss's latest messages:\n#{Enum.join(ctx.boss, "\n")}"
       end},
      {:chat, fn ctx, s -> if Enum.any?(ctx.crew, &(&1.name != s.name)), do: 22, else: 0 end, &chat_ask/2},
      {:shipped, fn ctx, _s -> if ctx.finished == [], do: 0, else: 5 end,
       fn ctx, s ->
         "#{s.name} celebrates or grumbles about something just finished: \"#{Enum.random(ctx.finished)}\""
       end}
    ]
  end

  @doc """
  Draw a kind by weight for `speaker`: `{name, prompt}`, or nil when every weight is 0. `roll` in
  [0, 1) picks the point on the weighted line — `:rand.uniform/0` in the office, fixed in a test.
  """
  def pick(ctx, speaker, roll \\ :rand.uniform()) do
    weighted = for {name, weight, ask} <- kinds(), w = weight.(ctx, speaker), w > 0, do: {name, w, ask}
    total = weighted |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    if total > 0 do
      {name, _, ask} = at(weighted, roll * total)
      {name, ask.(ctx, speaker)}
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @doc "The situations the room may ask two coworkers to talk in, by key."
  def situations, do: Map.keys(@situations)

  @doc """
  Two coworkers, `a` and `b`, are together in the room — at ping-pong, on the couch, passing in the
  hall (`situations/0`) — and the room asks what they say: one fresh conversation, written now by
  `Server.Office.Writer` from who they are, what each is working on and what the office has been up
  to. `{:ok, [%{"who", "line"}]}` with 2 to 4 turns; `{:error, :busy}` when this workspace had a
  conversation in the last `@talk_every_s` or this pair in the last `@pair_every_s` (the room just
  lets them be quiet); `{:error, :unknown}` for a situation or a person it does not know.
  """
  def talk(ws, situation, a, b) do
    with true <- Map.has_key?(@situations, situation) and a != b,
         true <- Server.Office.Writer.tone() != nil or Application.get_env(:server, :banter_cmd) != nil,
         ctx = context(ws),
         [%{} = pa, %{} = pb] <- Enum.map([a, b], fn n -> Enum.find(ctx.crew, &(&1.name == n)) end),
         :ok <- reserve(ws, a, b) do
      ask =
        "#{who(pa)} and #{who(pb)} #{@situations[situation]}. They talk about what they are doing right " <>
          "now, their work, each other, or the office's day."

      with {:ok, out} <- Server.Office.Writer.write(@chat_voice <> "\n" <> scene(ctx) <> "\n\nNOW: " <> ask, ws),
           [_, _ | _] = turns <- parse_chat(out, MapSet.new([a, b])) do
        {:ok, turns}
      else
        # a write that failed spent nothing: the pair may talk again at the next sighting
        _ ->
          release(ws, a, b)
          {:error, :unwritten}
      end
    else
      {:error, :busy} -> {:error, :busy}
      _ -> {:error, :unknown}
    end
  end

  @impl true
  def handle_call({:reserve, ws, pair}, _from, state) do
    now = System.system_time(:second)
    %{talked: last, pairs: pairs} = Map.get(state, {:talk, ws}, %{talked: 0, pairs: %{}})

    if now - last < Server.Office.Writer.every(@talk_every_s) or
         now - Map.get(pairs, pair, 0) < Server.Office.Writer.every(@pair_every_s),
       do: {:reply, {:error, :busy}, state},
       else: {:reply, :ok, Map.put(state, {:talk, ws}, %{talked: now, pairs: Map.put(pairs, pair, now)})}
  end

  def handle_call({:lines, ws}, _from, state) do
    now = System.system_time(:second)
    %{lines: lines, at: at, busy: busy} = Map.get(state, ws, %{lines: [], at: 0, busy: false})
    lines = Enum.filter(lines, &(now - &1.at < @keep_s))
    ask? = not busy and now - at >= Server.Office.Writer.every(@every_s)
    if ask?, do: start_line(ws)
    {:reply, lines, Map.put(state, ws, %{lines: lines, at: if(ask?, do: now, else: at), busy: busy or ask?})}
  end

  @impl true
  def handle_cast({:release, ws, pair}, state) do
    entry = Map.get(state, {:talk, ws}, %{talked: 0, pairs: %{}})
    {:noreply, Map.put(state, {:talk, ws}, %{talked: 0, pairs: Map.delete(entry.pairs, pair)})}
  end

  def handle_cast({:said, ws, said}, state) do
    entry = Map.get(state, ws, %{lines: [], at: 0, busy: false})
    now = System.system_time(:second)
    lines = entry.lines ++ for(s <- List.wrap(said), do: Map.put(s, :at, now))
    {:noreply, Map.put(state, ws, %{entry | lines: lines, busy: false})}
  end

  @doc false
  def write_line(ws) do
    ctx = context(ws)

    with [_ | _] <- ctx.crew,
         speaker = Enum.random(ctx.crew),
         {kind, ask} <- pick(ctx, speaker),
         voice = if(kind == :chat, do: @chat_voice, else: @voice),
         {:ok, out} <- Server.Office.Writer.write(voice <> "\n" <> scene(ctx) <> "\n\nNOW: " <> ask, ws) do
      said(kind, out, speaker, ctx)
    else
      _ -> nil
    end
  end

  @doc false
  def parse_chat(out, names) do
    Server.JsonBlob.first_valid(out, fn
      %{"turns" => turns} when is_list(turns) ->
        for %{"who" => who, "line" => line} <- turns,
            is_binary(who) and is_binary(line),
            MapSet.member?(names, who),
            line = String.trim(line),
            line != "",
            do: %{"who" => who, "line" => String.slice(line, 0, 90)}

      _ ->
        nil
    end)
  end

  # two of the crew talk: preferably two who work together (`partners/2`), about that work
  defp chat_ask(ctx, s) do
    {partner, together} =
      case partners(ctx, s) do
        [] -> {Enum.random(Enum.reject(ctx.crew, &(&1.name == s.name))), false}
        ps -> {Enum.random(ps), true}
      end

    about =
      if together,
        do:
          "They are working together — one staffed the other, or one's thread sits under the other's: talk about that shared work, how it is going, what one needs from the other.",
        else: "Talk about what each is doing, or anything at all: office life, the boss, a running joke."

    "#{s.name} (#{s.archetype}, #{if s.thread, do: thread_line(s.thread), else: "idle"}) and #{partner.name} (#{partner.archetype}, #{if partner.thread, do: thread_line(partner.thread), else: "idle"}) have a quick conversation. #{about}"
  end

  @doc """
  Whom `s` is working with, among the crew here: the lead of the thread above theirs and the leads
  of the open threads under it — the one who staffed them, the ones they staffed. `[]` when none.
  """
  def partners(ctx, s) do
    with %{id: id} <- s.thread, %Server.Thread{} = t <- Server.Channel.thread(id) do
      under =
        Server.Repo.all(from c in Server.Thread, where: c.parent_thread_id == ^id and c.state == "open", select: c.id)

      names =
        [t.parent_thread_id | under]
        |> Enum.reject(&is_nil/1)
        |> MapSet.new(&Server.Channel.thread_lead/1)
        |> MapSet.delete(s.name)

      Enum.filter(ctx.crew, &MapSet.member?(names, &1.name))
    else
      _ -> []
    end
  end

  @doc false
  def parse(out) do
    Server.JsonBlob.first_valid(out, fn
      %{"line" => l} when is_binary(l) -> if String.trim(l) != "", do: String.slice(String.trim(l), 0, 90)
      _ -> nil
    end)
  end

  @doc false
  # Who is here and what everyone is on, gathered once per line (and per pet batch, `Server.Office.Pets`).
  def context(ws) do
    status = Server.Office.status()
    threads = for t <- status.threads, t.workspace_id == ws, into: %{}, do: {t.lead, t}

    crew =
      for b <- status.bench, b.workspace_id == ws do
        %{
          name: b.name,
          archetype: b.archetype || "coworker",
          lead: b.lead,
          thread: threads[b.name],
          persona: persona_line(Server.Persona.get(ws, b.name))
        }
      end

    boss =
      80
      |> Server.Channel.recent_across()
      |> Enum.filter(&Server.Channel.operator?(&1.author))
      |> Enum.take(-5)
      |> Enum.map(&~s|- "#{clip(&1.body, 160)}" (on "#{&1.thread_title}")|)

    %{
      crew: crew,
      operator: Application.get_env(:server, :operator, "andrew"),
      awaiting: Enum.count(status.threads, &(&1.workspace_id == ws and &1.awaiting)),
      boss: boss,
      finished: ws |> Server.Office.archive() |> Map.fetch!(:threads) |> Enum.take(5) |> Enum.map(& &1.title),
      tickets: for(t <- status.tickets, t.workspace_id == ws, do: t.title)
    }
  end

  @doc false
  def scene(ctx) do
    people =
      Enum.map_join(ctx.crew, "\n", fn c ->
        "- #{c.name}, #{c.archetype}#{if c.lead, do: " (tech lead)"}: #{if c.thread, do: thread_line(c.thread), else: "on the bench, idle"}" <>
          if(c[:persona], do: "\n  who they are: #{c.persona}", else: "")
      end)

    "THE OFFICE:\n#{people}\nTickets waiting: #{ctx.tickets |> Enum.take(5) |> Enum.join("; ")}"
  end

  defp others(ctx, s), do: Enum.filter(ctx.crew, &(&1.name != s.name and &1.thread))

  # a seat's persona (`Server.Persona`) as one line for a prompt: how they talk and what they're like
  defp persona_line(%{"voice" => voice} = p) do
    q = p["quirks"] || %{}

    [
      voice,
      q["catchphrase"] && ~s(says "#{q["catchphrase"]}"),
      q["pet_peeve"] && "can't stand #{q["pet_peeve"]}",
      q["hobby"] && "into #{q["hobby"]}"
    ]
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.join("; ")
  end

  defp persona_line(_), do: nil

  defp thread_line(t),
    do: "##{t.id} \"#{t.title}\"#{if t.stage, do: " (#{t.stage})"}#{if t.awaiting, do: ", waiting on the boss"}"

  defp recent(%{id: id}) do
    case Server.Channel.thread(id) do
      nil -> ""
      t -> t |> Server.Channel.recent_messages(2) |> Enum.map_join("\n", &"- #{&1.author}: #{clip(&1.body, 200)}")
    end
  end

  defp clip(s, n), do: s |> String.replace(~r/\s+/, " ") |> String.slice(0, n)

  defp start_line(ws) do
    me = self()
    # the cast is what clears `busy`: a line that raises still sends it, or banter stops for good
    Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
      said =
        try do
          write_line(ws)
        rescue
          _ -> nil
        end

      GenServer.cast(me, {:said, ws, said})
    end)
  end

  # the kind whose stretch of the weighted line holds `point`
  defp at([{_, w, _} = k | rest], point), do: if(point < w or rest == [], do: k, else: at(rest, point - w))

  # a remark is one line from its speaker; a chat is its turns, each `delay` seconds after the first
  defp said(:chat, out, _speaker, ctx) do
    case parse_chat(out, MapSet.new(ctx.crew, & &1.name)) do
      [_, _ | _] = turns ->
        for {%{"who" => who, "line" => line}, i} <- Enum.with_index(turns),
            do: %{agent: who, line: line, kind: :chat, delay: i * @turn_s}

      _ ->
        nil
    end
  end

  defp said(kind, out, speaker, _ctx) do
    with line when is_binary(line) <- parse(out), do: [%{agent: speaker.name, line: line, kind: kind, delay: 0}]
  end

  defp release(ws, a, b),
    do: if(GenServer.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:release, ws, Enum.sort([a, b])}))

  defp reserve(ws, a, b),
    do: if(GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:reserve, ws, Enum.sort([a, b])}), else: :ok)

  # who someone is, for a conversation: their role, what they are on and its latest words
  defp who(c) do
    on = if c.thread, do: "on #{thread_line(c.thread)}, where lately:\n#{recent(c.thread)}\n", else: "idle"
    "#{c.name} (#{c.archetype}, #{on})"
  end
end
