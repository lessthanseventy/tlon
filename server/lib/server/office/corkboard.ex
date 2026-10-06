defmodule Server.Office.Corkboard do
  @moduledoc """
  The office corkboard: notes the coworkers pin up for each other — encouragement, a tease, a joke,
  a comment on what's going on, a suggestion (a bug they suspect, a fix they'd try), or a reply to
  an earlier note, which is how a feud or a running joke starts. Written by the cheap tier like the
  banter (`Server.Office.Banter`, whose scene of the office it reuses); the server picks the author
  and the kind (`pick/4`), the model only writes it.

  Office chatter, not working memory: kept in memory here, the newest `@keep` per workspace, and
  never written to `Server.Notes`, which the coworkers read as they work. A suggestion goes in the
  suggestion box instead (`suggestions/1`, the newest `@keep_ideas`), apart from the chatter so it
  is never crowded out by it; it leaves the box when the operator files it as a ticket or throws
  it out (`drop/2`). Lazy like banter — a note is only written while an office
  asks (`notes/1`), at most one per workspace every `@every_s` — and on and off with it.
  """
  use GenServer

  alias Server.Office.Banter

  @every_s 480
  @keep 12
  @keep_ideas 20
  @voice """
  You write ONE sticky note a coworker pins on the corkboard of a pixel-art office of AI coworkers,
  for the others to read. Under 120 characters; in character for their role; dry, warm, a little
  absurd; teasing is affectionate, a feud is petty and funny, never cruel; no emoji, no hashtags.
  Respond with ONLY a JSON object: {"note": "<the note>"}
  """

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  The workspace's corkboard, newest first: `%{id, author, kind, body, re, at}` (`re` the id of the
  note it answers; `at` unix seconds) — and, when the last note is stale, a new one asked for in the
  background. `[]` where banter is off.
  """
  @spec notes(integer()) :: [map()]
  def notes(workspace_id) do
    if GenServer.whereis(__MODULE__) && Server.OperatorConfig.banter?(),
      do: GenServer.call(__MODULE__, {:notes, workspace_id}),
      else: []
  end

  @doc "The suggestion box, newest first: the suggestions not yet filed or thrown out, shaped as `notes/1`'s."
  @spec suggestions(integer()) :: [map()]
  def suggestions(workspace_id) do
    if GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:suggestions, workspace_id}), else: []
  end

  @doc "Take suggestion `id` out of the box — filed as a ticket, or thrown out. `:ok` either way."
  @spec drop(integer(), integer()) :: :ok
  def drop(workspace_id, id) do
    if GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:drop, workspace_id, id}), else: :ok
  end

  @doc """
  Draw a kind of note for `author` by weight: `{kind, ask, re}` (`re` the note a reply answers),
  or nil when nothing fits. A reply needs someone else's note; a tease, someone to tease; a
  suggestion, work in hand. `roll` in [0, 1) picks the point on the weighted line.
  """
  def pick(ctx, board, author, roll \\ :rand.uniform()) do
    others = Enum.filter(ctx.crew, &(&1.name != author.name))
    theirs = Enum.filter(board, &(&1.author != author.name))
    working = Enum.filter(ctx.crew, & &1.thread)

    kinds =
      [
        {:encourage, 20, fn -> encourage(others, author) end},
        {:joke, 15,
         fn -> "#{author.name} pins a joke — programmer humour, office life, or about being a #{author.archetype}." end},
        {:comment, 15,
         fn -> "#{author.name} comments on something going on in the office right now (see THE OFFICE)." end}
      ] ++
        if(others == [], do: [], else: [{:tease, 15, fn -> tease(Enum.random(others), author) end}]) ++
        if(working == [], do: [], else: [{:suggestion, 10, fn -> suggestion(Enum.random(working), author) end}]) ++
        if(theirs == [], do: [], else: [{:reply, 25, fn -> theirs |> Enum.take(4) |> Enum.random() end}])

    total = kinds |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    {kind, _, ask} = at(kinds, roll * total)

    case {kind, ask.()} do
      {:reply, note} ->
        {:reply,
         "#{author.name} pins a reply to #{note.author}'s #{note.kind} note: \"#{note.body}\" — agree, argue, one-up or keep the bit going; address #{note.author} by name.",
         note.id}

      {kind, ask} ->
        {kind, ask, nil}
    end
  end

  defp encourage([], author), do: "#{author.name} pins a note of encouragement for the whole crew."

  defp encourage(others, author),
    do: "#{author.name} pins a note of encouragement for #{Enum.random(others).name}, about what they're doing."

  defp tease(other, author),
    do:
      "#{author.name} pins an affectionate tease of #{other.name} (#{other.archetype}) — their habits, their work, their quirks."

  defp suggestion(worker, author),
    do:
      "#{author.name} pins a suggestion about #{worker.name}'s work on ##{worker.thread.id} \"#{worker.thread.title}\" — a bug they suspect or a fix they'd try. Concrete, one line."

  defp at([{_, w, _} = k | rest], point), do: if(point < w or rest == [], do: k, else: at(rest, point - w))

  @doc false
  def parse(out) do
    Server.JsonBlob.first_valid(out, fn
      %{"note" => n} when is_binary(n) -> if String.trim(n) != "", do: String.slice(String.trim(n), 0, 140)
      _ -> nil
    end)
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:notes, ws}, _from, state) do
    now = System.system_time(:second)
    entry = entry(state, ws)

    if now - entry.at >= @every_s do
      me = self()
      board = entry.notes
      Task.Supervisor.start_child(Server.TaskSupervisor, fn -> GenServer.cast(me, {:pinned, ws, write(ws, board)}) end)
    end

    {:reply, entry.notes, Map.put(state, ws, %{entry | at: if(now - entry.at >= @every_s, do: now, else: entry.at)})}
  end

  def handle_call({:suggestions, ws}, _from, state), do: {:reply, entry(state, ws).ideas, state}

  def handle_call({:drop, ws, id}, _from, state) do
    entry = entry(state, ws)
    {:reply, :ok, Map.put(state, ws, %{entry | ideas: Enum.reject(entry.ideas, &(&1.id == id))})}
  end

  @impl true
  def handle_cast({:pinned, _ws, nil}, state), do: {:noreply, state}

  def handle_cast({:pinned, ws, note}, state) do
    entry = entry(state, ws)
    note = Map.merge(note, %{id: entry.next, at: System.system_time(:second)})

    entry =
      if note.kind == "suggestion",
        do: %{entry | ideas: Enum.take([note | entry.ideas], @keep_ideas)},
        else: %{entry | notes: Enum.take([note | entry.notes], @keep)}

    {:noreply, Map.put(state, ws, %{entry | next: entry.next + 1})}
  end

  defp entry(state, ws), do: Map.get(state, ws, %{notes: [], ideas: [], at: 0, next: 1})

  defp write(ws, board) do
    ctx = Banter.context(ws)

    with [_ | _] <- ctx.crew,
         author = Enum.random(ctx.crew),
         {kind, ask, re} <- pick(ctx, board, author),
         {:ok, out} <-
           Server.ModelCli.prompt(
             @voice <> "\n" <> Banter.scene(ctx) <> board_text(board) <> "\n\nNOW: " <> ask,
             :banter_cmd,
             :banter_model,
             {"pi", "ollama-cloud/deepseek-v4.1-flash"}
           ),
         body when is_binary(body) <- parse(out) do
      %{author: author.name, kind: to_string(kind), body: body, re: re}
    else
      _ -> nil
    end
  end

  defp board_text([]), do: ""

  defp board_text(board),
    do: "\nON THE CORKBOARD:\n" <> Enum.map_join(Enum.take(board, 6), "\n", &"- #{&1.author} (#{&1.kind}): #{&1.body}")
end
