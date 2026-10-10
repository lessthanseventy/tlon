defmodule Server.Office.Pets do
  @moduledoc """
  The pets' voices: what Nina and Argos say, written in each one's personality by a cheap model in a
  drawn mood (`Server.Office.Writer`, which follows the shift) — a personality, not a script.

  An office reacts to its pets instantly (a pat cannot wait on a model), so this does not write one
  line at a time: it writes a batch per pet, a few lines for each OCCASION (`occasions/1`: patted,
  woken, a coworker starting a test, a treat…), about this office as it is now (`Banter.scene/1`), and
  the office picks from the batch as things happen; a line about a coworker carries `{name}` for the
  office to fill in. Lazy like banter: batches are only written while an office asks (`voices/1`), at
  most one round (each pet's and the pair's) per workspace every `@every_s`, sooner the wilder the
  dial (`Server.Office.Writer.every/2`), and at once when the dial turns. On and off with banter
  (`Server.Office.Banter`). A reply that does not parse is dropped; a good one joins the last few
  batches at its level (up to `@keep` lines an occasion), so lines from different writers and moods
  mix, or replaces them when the level changed.

  The scene is more than who sits where (`context/1`): what landed today, the last of the lobby's
  talk (releases, restarts, shift changes and what people said), the shift, the weather and the time
  of day, so the lines are about this evening, not any evening. Besides each pet's own batch there is
  the pair's (`"duo"`): their exchanges for the antics they get up to together and the chats they
  have when both are idle, each exchange a list of `"Nina: …"` / `"Argos: …"` turns.
  """
  use GenServer

  alias Server.Office.Banter

  @every_s 300
  @pets %{
    "Nina" => """
    Nina, the office cat: a black cat with yellow eyes and a jewelled collar she adores. A princess and
    a diva — sassy, vain, imperious, dramatic; sure the office exists to admire her and that she ought
    to be running it; secretly fond of everyone and never admits it. She calls people "peasant" and
    "darling", and mentions her fans, her awards and her collar.
    """,
    "Argos" => """
    Argos, the office dog: a golden good boy who is the troglodyte of Borges' "The Immortal" — that is,
    Homer, who wrote the Iliad and the Odyssey and has forgotten nearly all of it. Overjoyed by
    everything, above all walks, treats and belly rubs; now and then a scrap of epic surfaces (the
    wine-dark sea, rosy-fingered dawn, Troy, Ithaca, the Muse) and is lost again to a squirrel.
    """
  }
  @lines_per 5
  @keep 15
  @duo %{
    "sneak" => "Argos creeps up on Nina and shouts BOO; she is outraged",
    "bap" => "Nina bats the sleeping Argos awake",
    "chase" => "the two of them have just chased each other round the room, and stop, out of breath",
    "scuffle" => "a short scuffle, fur flying, then a truce",
    "chat" =>
      "both are idle on the floor and talk about what is going on in the office today (the news below): 2 to 4 turns"
  }
  @tools ~w(read edit bash search web test delegate)
  @fusses %{
    "fuss_pat" => "{name}, a coworker, gives a pat on the head",
    "fuss_scratch" => "{name} gives a good scratch behind the ears",
    "fuss_belly" => "{name} goes for a belly rub",
    "fuss_treat" => "{name} tosses over a treat"
  }

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Each pet's lines for this workspace, by name then occasion — `%{"Nina" => %{"pet" => [line]}}`,
  and the pair's exchanges under `"duo"` (`%{"chat" => [["Nina: …", "Argos: …"]]}`) — and, when a
  batch is stale, a new one asked for in the background. `%{}` where this is off.
  """
  @spec voices(integer()) :: %{String.t() => %{String.t() => [String.t() | [String.t()]]}}
  def voices(workspace_id, cat \\ nil) do
    if GenServer.whereis(__MODULE__) && Server.OperatorConfig.banter?(),
      do: GenServer.call(__MODULE__, {:voices, workspace_id, cat}),
      else: %{}
  end

  @doc """
  The cat slot as the office has it configured (its `pets.json`: name, species, and a temperament of
  warmth, wits and energy from -2 to 2), in words for a prompt; "" when the office sent none.
  """
  def temperament(%{} = cat) do
    words = [
      axis(cat["warmth"], ["icy, a menace", "prickly", nil, "affectionate", "sweet as pie"]),
      axis(cat["wits"], ["dim", "scatterbrained", nil, "sharp", "a scheming genius"]),
      axis(cat["energy"], ["lazy", "sleepy", nil, "playful", "bouncing off the walls"])
    ]

    "IN THIS OFFICE: the cat slot is #{word(cat["name"], "Nina")}, a #{word(cat["species"], "cat")}" <>
      case Enum.reject(words, &is_nil/1) do
        [] -> "."
        ws -> "; temperament: #{Enum.join(ws, ", ")}. Let it colour every line."
      end
  end

  def temperament(_), do: ""

  @doc "A pet's occasions, `{name, what happened}`: what it may be asked to say something about."
  def occasions("Nina") do
    [
      {"pet", "the boss clicks on her to pet her"},
      {"wake", "she is woken from a nap"},
      {"muse", "she thinks aloud, unprompted — about herself, the office, or a coworker by name"}
    ] ++
      tool_occasions() ++
      [
        {"done", "{name} finishes a turn of work"},
        {"queue", "{name} is now waiting on the boss"},
        {"shipped", "{name}'s work just shipped — confetti over them, the office cheering"},
        {"fish", "she sits at the aquarium, pawing at the glass, the fish gathered just out of reach"},
        {"nap", "the boss tells her to go and nap"},
        {"play", "the boss tells her to play with her yarn"},
        {"come", "the boss calls her over to their desk"},
        {"zoomies", "the boss sets off her zoomies"}
      ] ++ Enum.to_list(@fusses)
  end

  def occasions("Argos") do
    [
      {"pat", "the boss pats him while he is out and about"},
      {"belly", "he rolls over for a belly rub from the boss"},
      {"muse", "he thinks aloud, unprompted — about walks, the office, a coworker by name, or a scrap of epic"},
      {"test", "{name} starts running the tests"},
      {"done", "{name} finishes a turn of work"},
      {"queue", "{name} is now waiting on the boss"},
      {"shipped", "{name}'s work just shipped — confetti over them, the office cheering"},
      {"rally", "he watches two coworkers play ping-pong, his head going with the ball"},
      {"visit", "he trots over to sit by {name} at their desk"},
      {"walk", "the boss tells him to go for a walk"},
      {"office", "the boss calls him into their office"},
      {"sit", "the boss tells him to sit"},
      {"bed", "the boss sends him to his bed"}
    ] ++ Enum.to_list(@fusses)
  end

  defp tool_occasions, do: for(t <- @tools, do: {t, "{name} starts a #{t} tool (#{t}: #{tool_gloss(t)})"})

  defp tool_gloss("read"), do: "reading files"
  defp tool_gloss("edit"), do: "editing code"
  defp tool_gloss("bash"), do: "running a shell command"
  defp tool_gloss("search"), do: "searching the code"
  defp tool_gloss("web"), do: "looking something up on the web"
  defp tool_gloss("test"), do: "running the tests"
  defp tool_gloss("delegate"), do: "handing work to another coworker"

  @doc """
  The office as the pets see it: `Banter.context/1` plus what has been happening — `landed` (titles
  that merged in the last 12 hours), `lobby` (the server's own last announcements on the workspace's
  standing thread — releases, restarts, landings, shift changes — never what a person or a coworker
  wrote there, which can hold paths, pasted output or the operator's asks and would go to an outside
  model), `shift`, `weather` and `clock` (the part of the day, local time).
  """
  def context(ws) do
    root = Server.Channel.machine_thread(ws)
    since = DateTime.add(DateTime.utc_now(), -12 * 3600, :second)

    Map.merge(Banter.context(ws), %{
      landed: since |> Server.Workline.landed_since() |> Enum.map(& &1.title) |> Enum.uniq() |> Enum.take(6),
      lobby:
        if(root,
          do:
            Enum.take(
              for(
                m <- Server.Channel.recent_messages(root, 40),
                m.author == "tlon",
                do: m.body |> String.split("\n", parts: 2) |> hd() |> clip()
              ),
              -8
            ),
          else: []
        ),
      shift: Server.Shifts.current(ws),
      weather: Server.Office.Weather.now(),
      clock: clock(:calendar.local_time())
    })
  end

  @doc false
  def clock({{_, _, _}, {h, _, _}}) do
    cond do
      h < 5 -> "the small hours of the night"
      h < 12 -> "morning"
      h < 17 -> "afternoon"
      h < 21 -> "evening"
      true -> "late evening"
    end
  end

  @doc "The scene a pet's lines are about: who is here (`Banter.scene/1`), then what has been happening."
  def scene(ctx) do
    news =
      Enum.filter(
        [
          ctx[:clock] && "It is #{ctx.clock}#{if ctx[:shift] == "night", do: ", and the night crew is on"}.",
          outside(ctx[:weather]),
          listed("Shipped today: ", ctx[:landed], "; ", "."),
          listed("Lately in the lobby:\n- ", ctx[:lobby], "\n- ", "")
        ],
        &is_binary/1
      )

    Enum.join([Banter.scene(ctx) | if(news == [], do: [], else: ["WHAT'S BEEN HAPPENING:" | news])], "\n")
  end

  @doc "What `pet` is asked: its personality, the office (`ctx` as `context/1` gives it), its occasions."
  def prompt(pet, ctx) do
    asks = Enum.map_join(occasions(pet), "\n", fn {k, what} -> ~s(- "#{k}": #{what}) end)

    """
    You write the lines of #{pet}, a pet in a pixel-art office of AI coworkers; each line is said
    out loud in a speech balloon over the pet.
    WHO #{String.upcase(pet)} IS: #{@pets[pet]}
    #{if pet == "Nina", do: ctx[:cat]}
    #{scene(ctx)}

    For EACH occasion below write #{@lines_per} different lines, each under 100 characters, in
    character and funny; vary them in shape and length, and let several of them pick up something
    from what's been happening (a thing that shipped, something said in the lobby, the hour, the
    weather) rather than only the occasion itself. Where a line is about a coworker, write {name} for
    them, or use the names above; a coworker is "they", never "he" or "she". No emoji, never cruel.
    Respond with ONLY a JSON object:
    {"lines": {"<occasion>": ["...", ...], ...}}
    OCCASIONS:
    #{asks}
    """
  end

  @doc "What the pair is asked: both personalities, the office, and the exchanges they have together."
  def prompt_duo(ctx) do
    asks = Enum.map_join(@duo, "\n", fn {k, what} -> ~s(- "#{k}": #{what}) end)

    """
    You write short exchanges between the two pets of a pixel-art office of AI coworkers; each turn
    is said out loud in a speech balloon over the pet who says it.
    WHO NINA IS: #{@pets["Nina"]}
    #{ctx[:cat]}
    WHO ARGOS IS: #{@pets["Argos"]}
    #{scene(ctx)}

    For EACH occasion below write 4 different exchanges. An exchange is 2 to 4 turns, alternating,
    each turn "Nina: ..." or "Argos: ..." and under 90 characters. Keep each in character; make them
    funny and different from each other; the chats are about what's been happening, by name. A
    coworker is "they", never "he" or "she". No emoji, never cruel. Respond with ONLY a JSON object:
    {"exchanges": {"<occasion>": [["Argos: ...", "Nina: ..."], ...], ...}}
    OCCASIONS:
    #{asks}
    """
  end

  @doc false
  def parse(out, pet) do
    keys = MapSet.new(occasions(pet), &elem(&1, 0))

    Server.JsonBlob.first_valid(out, fn
      %{"lines" => lines} when is_map(lines) ->
        for {k, ls} <- lines, k in keys, is_list(ls), ls = clean(ls), ls != [], into: %{}, do: {k, ls}

      _ ->
        nil
    end)
  end

  @doc false
  def parse_duo(out) do
    Server.JsonBlob.first_valid(out, fn
      %{"exchanges" => ex} when is_map(ex) ->
        for {k, list} <- ex,
            Map.has_key?(@duo, k),
            is_list(list),
            list = exchanges(list),
            list != [],
            into: %{},
            do: {k, list}

      _ ->
        nil
    end)
  end

  defp clean(lines), do: for(l <- lines, is_binary(l), l = String.trim(l), l != "", do: String.slice(l, 0, 100))

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:voices, ws, cat}, _from, state) do
    now = System.system_time(:second)
    level = Server.Office.Writer.level()
    entry = Map.merge(%{voices: %{}, at: 0, asked: nil, tones: %{}}, Map.get(state, ws, %{}))
    # a turned dial is heard at once, not at the next round
    due? = now - entry.at >= Server.Office.Writer.every(@every_s, level) or entry.asked != level

    if due?, do: ask(ws, cat, level)

    {:reply, entry.voices, Map.put(state, ws, if(due?, do: %{entry | at: now, asked: level}, else: entry))}
  end

  @impl true
  def handle_cast({:wrote, _ws, _pet, nil, _level}, state), do: {:noreply, state}

  # a batch at a new level replaces the pet's lines, so the new tone isn't diluted by the old
  def handle_cast({:wrote, ws, pet, lines, level}, state) do
    entry = Map.merge(%{voices: %{}, at: 0, asked: nil, tones: %{}}, Map.get(state, ws, %{}))
    kept = if entry.tones[pet] == level, do: merged(entry.voices[pet], lines), else: lines

    {:noreply,
     Map.put(state, ws, %{entry | voices: Map.put(entry.voices, pet, kept), tones: Map.put(entry.tones, pet, level)})}
  end

  # a new batch joins the last ones instead of replacing them, so lines from different writers and
  # flavours mix: the newest first, the oldest dropped past `@keep` per occasion
  defp merged(nil, lines), do: lines

  defp merged(old, lines),
    do: Map.merge(old, lines, fn _occasion, was, new -> Enum.take(Enum.uniq(new ++ was), @keep) end)

  defp ask(ws, cat, level) do
    me = self()

    Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
      write_round(me, ws, Map.put(context(ws), :cat, temperament(cat)), level)
    end)
  end

  defp write_round(me, ws, ctx, level) do
    for pet <- ["duo" | Map.keys(@pets)],
        do:
          Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
            GenServer.cast(me, {:wrote, ws, pet, write(ws, ctx, pet), level})
          end)
  end

  defp write(ws, ctx, pet) do
    {ask, parse} = if pet == "duo", do: {prompt_duo(ctx), &parse_duo/1}, else: {prompt(pet, ctx), &parse(&1, pet)}

    with {:ok, out} <- Server.Office.Writer.write(ask, ws),
         %{} = lines when map_size(lines) > 0 <- parse.(out) do
      lines
    else
      _ -> nil
    end
  end

  defp clip(s), do: s |> String.replace(~r/\s+/, " ") |> String.slice(0, 140)

  # an exchange is two or more turns, each said by one of the pair
  defp exchanges(list) do
    for turns <- list,
        is_list(turns),
        turns = Enum.map(clean(turns), &String.slice(&1, 0, 107)),
        length(turns) >= 2,
        Enum.all?(turns, &String.match?(&1, ~r/\A(Nina|Argos):\s*\S/)),
        do: turns
  end

  defp outside(%{} = weather),
    do: with(desc when is_binary(desc) <- weather[:desc] || weather["desc"], do: "Outside: #{desc}.")

  defp outside(_), do: nil

  defp listed(_head, items, _sep, _tail) when items in [nil, []], do: nil
  defp listed(head, items, sep, tail), do: head <> Enum.join(items, sep) <> tail

  defp axis(n, words) when is_integer(n) and n in -2..2, do: Enum.at(words, n + 2)
  defp axis(_, _), do: nil

  # a name from the office's poll, for a prompt: one short line, never a paragraph someone pasted
  defp word(s, fallback) when is_binary(s) do
    s
    |> String.replace(~r/[[:cntrl:]]/, " ")
    |> String.trim()
    |> String.slice(0, 32)
    |> case do
      "" -> fallback
      w -> w
    end
  end

  defp word(_, fallback), do: fallback
end
