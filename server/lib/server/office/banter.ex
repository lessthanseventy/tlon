defmodule Server.Office.Banter do
  @moduledoc """
  The office's small talk: now and then a coworker says something — about their work, someone
  else's, the boss, the room, or just a joke — written by the cheap model tier
  (`Server.ModelCli`; `config :server, banter_cmd:, banter_model:`, default `pi` on
  `ollama-cloud/deepseek-v4.1-flash`, the flat ollama bucket).

  Each line is one of several KINDS of remark (`kinds/0`), drawn by weight (`pick/2`); a kind's
  weight reads the moment, so one that has nothing to say about it (no one else working, nothing
  finished) is never drawn. The server picks the speaker and the kind; the model only writes it.

  Lazy on purpose: a line is only written while an office asks (`lines/1` from its poll), at most
  one per workspace every `@every_s`, so a room nobody watches costs nothing. On by default: a node
  runs it unless `TLON_BANTER=0` (`:start_banter`), and the operator's settings file switches it off
  live (`"banter": false`, `Server.OperatorConfig.banter?/0`, flipped from the office's settings).
  A reply that does not parse is dropped.
  """
  use GenServer

  @every_s 120
  @keep_s 300
  @voice """
  You write ONE line of small talk for a coworker in a pixel-art office of AI coworkers, said out
  loud as they walk around. Under 80 characters. Dry, warm, a little absurd; in character for their
  role; no emoji, no hashtags, never cruel, never a list. Respond with ONLY a JSON object:
  {"line": "<what they say>"}
  """

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  The workspace's recent lines, oldest first, as `%{agent, line, kind, at}` (`at` in unix seconds) —
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

  @impl true
  def handle_call({:lines, ws}, _from, state) do
    now = System.system_time(:second)
    %{lines: lines, at: at, busy: busy} = Map.get(state, ws, %{lines: [], at: 0, busy: false})
    lines = Enum.filter(lines, &(now - &1.at < @keep_s))
    ask? = not busy and now - at >= @every_s
    if ask?, do: start_line(ws)
    {:reply, lines, Map.put(state, ws, %{lines: lines, at: if(ask?, do: now, else: at), busy: busy or ask?})}
  end

  @impl true
  def handle_cast({:said, ws, said}, state) do
    entry = Map.get(state, ws, %{lines: [], at: 0, busy: false})
    lines = if said, do: entry.lines ++ [Map.put(said, :at, System.system_time(:second))], else: entry.lines
    {:noreply, Map.put(state, ws, %{entry | lines: lines, busy: false})}
  end

  @doc false
  def write_line(ws) do
    ctx = context(ws)

    with [_ | _] <- ctx.crew,
         speaker = Enum.random(ctx.crew),
         {kind, ask} <- pick(ctx, speaker),
         {:ok, out} <-
           Server.ModelCli.prompt(
             @voice <> "\n" <> scene(ctx) <> "\n\nNOW: " <> ask,
             :banter_cmd,
             :banter_model,
             {"pi", "ollama-cloud/deepseek-v4.1-flash"}
           ),
         line when is_binary(line) <- parse(out) do
      %{agent: speaker.name, line: line, kind: kind}
    else
      _ -> nil
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
        %{name: b.name, archetype: b.archetype || "coworker", lead: b.lead, thread: threads[b.name]}
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
        "- #{c.name}, #{c.archetype}#{if c.lead, do: " (lead)"}: #{if c.thread, do: thread_line(c.thread), else: "on the bench, idle"}"
      end)

    "THE OFFICE:\n#{people}\nTickets waiting: #{ctx.tickets |> Enum.take(5) |> Enum.join("; ")}"
  end

  defp others(ctx, s), do: Enum.filter(ctx.crew, &(&1.name != s.name and &1.thread))

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
    Task.Supervisor.start_child(Server.TaskSupervisor, fn -> GenServer.cast(me, {:said, ws, write_line(ws)}) end)
  end

  # the kind whose stretch of the weighted line holds `point`
  defp at([{_, w, _} = k | rest], point), do: if(point < w or rest == [], do: k, else: at(rest, point - w))
end
