defmodule Server.Home.Pets do
  @moduledoc """
  What Nina and Argos say at home: lines written for the home as it is now (the time, the weather,
  what is open by name, what is coming, how much was done this week), a few for each occasion the
  house has (`occasions/0`), so a pat is answered at once from a batch and the batch is about this
  evening. A line about one open thing carries `{thing}` for the house to fill in.

  Lazy: a batch is written only while a house asks (`voices/1`), when there is none, when the home
  changed and the last is older than `@changed_s`, or when it is older than `@every_s`. The writer
  is the reader's model (`Server.Home.Reader`), since the scene holds what the operator jotted. A
  reply that does not parse leaves the last batch standing.

  The two pets are roles, `nina` and `argos`, each with a chosen name, animal and personality (the
  cast, `cast/1`). The batch held is for one cast: asked for another, it is dropped and written
  anew, and the caller gets `%{}` until that is done.
  """
  use GenServer

  alias Server.Home
  alias Server.Home.Clock

  @every_s 1800
  @changed_s 300
  @per 4
  @max 110

  @nina """
  a black cat with yellow eyes and a jewelled collar she adores. The smartest one in the house and
  sure of it: sharp, sassy, dry, a little imperious. She notices everything, has opinions on all of
  it, and wins every argument, mostly against the dog. Calls people "peasant" and "darling". Fond
  of the boss and would rather be shaved than say so.
  """
  @argos """
  a golden dog, sweet and not bright. Thrilled by everything, wrong about most of it, with total
  confidence: he mishears, misunderstands, loses the thread halfway through a thought, and believes
  whatever Nina tells him. Loves walks, treats, the boss, and Nina. Not every line is a shout: he
  is as often puzzled, earnest or quietly pleased with a wrong conclusion.
  """

  @defaults %{
    nina: %{name: "Nina", species: "cat", personality: "sassy"},
    argos: %{name: "Argos", species: "dog", personality: "sweet"}
  }

  @sketches %{
    "sassy" => """
    Sharp, sassy and dry, a little imperious. Notices everything, has opinions on all of it, and
    wins every argument, mostly against the other pet. Fond of the boss and would rather be
    shaved than say so.
    """,
    "sweet" => """
    Sweet and not bright. Thrilled by everything, wrong about most of it, with total confidence:
    mishears, misunderstands, loses the thread halfway through a thought. Not every line is a
    shout: as often puzzled, earnest or quietly pleased with a wrong conclusion.
    """,
    "lazy" => """
    Lazy and proud of it. Every plan is too far away and every chair is the right one. Speaks in
    yawns and half-sentences, is philosophical about naps, and is only ever roused by food or by
    someone else getting the good spot.
    """,
    "mischievous" => """
    Mischievous, always mid-scheme. Delighted by small chaos, an expert at looking innocent, and
    keeps a running list of things to knock over next. Never malicious, only curious about what
    happens if.
    """,
    "shy" => """
    Shy and gentle, a whisperer. Trails off, apologises to furniture, and is braver than it
    believes in small, sudden moments. Admires the other pet from a safe distance and loves the
    boss quietly.
    """,
    "bold" => """
    Bold and loud about it. Has never doubted a decision, announces plans like a general, and
    treats every doorway as a conquest. Generous with courage, short on caution, and certain the
    house is its kingdom.
    """
  }

  @occasions [
    {"pet", "the boss clicks on them to pet them"},
    {"wake", "they are woken from a nap"},
    {"muse", "they think aloud, unprompted, about anything at all"},
    {"done", "the boss just finished {thing}"},
    {"all_done", "the boss finished the last open thing; nothing is left"},
    {"old", "{thing} has sat undone for days"},
    {"jot", "the boss writes a new thing down"},
    {"ring", "a reminder is going off for {thing} and the boss has not answered"},
    {"home", "the boss comes home at the end of the day"},
    {"morning", "the boss appears in the morning"},
    {"tv", "the boss sits down in front of the television"},
    {"night", "it is late and the boss is still up"}
  ]

  def start_link(_) do
    state = %{lines: %{}, at: nil, asked: nil, key: nil, writing: nil, cast: @defaults}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  @doc """
  The cast a request asks for, `%{nina: pet, argos: pet}` with each `pet` `%{name, species,
  personality}`, from `params` (`nina_name`, `nina_species`, `nina_personality`, and the same for
  `argos`). A value that is missing or not well-formed is that role's default, so nothing else of
  the request reaches the prompt.
  """
  @spec cast(map()) :: %{nina: map(), argos: map()}
  def cast(params) do
    for {role, default} <- @defaults, into: %{} do
      {role,
       %{
         name: name(params["#{role}_name"], default.name),
         species: species(params["#{role}_species"], default.species),
         personality: personality(params["#{role}_personality"], default.personality)
       }}
    end
  end

  @doc "The occasions a batch has lines for, `{name, what happened}`."
  @spec occasions() :: [{String.t(), String.t()}]
  def occasions, do: @occasions

  @doc """
  The pets' lines at `now`, `%{"Nina" => %{occasion => [line]}, "Argos" => …, "duo" => [[turn]]}`,
  and a new batch asked for in the background when this one is stale. `%{}` before the first is
  written, and where this is off.
  """
  @spec voices(DateTime.t()) :: map()
  def voices(now), do: voices(now, @defaults)

  @doc """
  `voices/1` for `cast` (`cast/1`). The held batch is for one cast: asked for another, it is
  dropped, a batch for the new one is written, and the answer is `%{}` until it is.
  """
  @spec voices(DateTime.t(), %{nina: map(), argos: map()}) :: map()
  def voices(now, cast) do
    if GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:voices, now, cast}), else: %{}
  end

  @doc "The home at `now` as the writer is told it, from `status` (`Server.Home.status/1`) and the weather."
  @spec scene(map(), map() | nil, DateTime.t()) :: String.t()
  def scene(status, weather, now) do
    local = Clock.local(now)

    """
    It is #{Calendar.strftime(local, "%A %H:%M")}.#{weather(weather)}
    Open on the boss's list (#{length(status.open)}): #{things(status.open, now)}
    Coming up: #{coming(status.coming)}
    Done in the last seven days: #{status.done_week}.
    """
  end

  @doc "The prompt for one batch about `scene`, for the default cast."
  @spec prompt(String.t()) :: String.t()
  def prompt(scene), do: prompt(scene, @defaults)

  @doc """
  The prompt for one batch about `scene` for `cast`. The roles stay `Nina` and `Argos` in the
  answer's keys and turn prefixes; inside a line the pets may use each other's chosen names.
  """
  @spec prompt(String.t(), %{nina: map(), argos: map()}) :: String.t()
  def prompt(scene, cast) do
    """
    You write what two pets say in a small cosy game of the boss's home. Be funny: dry, specific,
    surprising. No stock pet jokes, no exclamation-mark cheer, nothing a greeting card would say.
    Each line under #{@max} characters, no emoji, no quotation marks around it. Always in the pet's own
    voice, first person, never narration about the pet. Do not describe what just happened (the boss
    can see it): react to it sideways. No two lines may share a joke or an image, and do not lean on
    the examples in the descriptions below; invent.

    NINA: #{describe(:nina, cast)}
    ARGOS: #{describe(:argos, cast)}
    #{naming(cast)}
    MOST lines are pure personality: who they are, what they want, their opinions, their schemes,
    each other, a non sequitur. Only about one line in four may touch the home as it is now (an open
    thing by its name, the hour, the weather), and only where the occasion calls for it or it is
    funnier that way. Never scold the boss about the list.

    THE HOME NOW, for that one line in four:
    #{scene}
    Write #{@per} different lines for each pet for each occasion below. Where an occasion names {thing},
    write the literal text {thing} in the line where the thing's name goes; use it in no other line.
    #{Enum.map_join(@occasions, "\n", fn {name, what} -> "- #{name}: #{what}" end)}

    Then "duo": #{@per} short exchanges between them (2 to 4 turns, each turn "Nina: …" or "Argos: …"):
    #{duo_voices(cast)}

    Answer with one JSON object and nothing else:
    {"Nina": {"pet": ["…"], …}, "Argos": {"pet": ["…"], …}, "duo": [["Nina: …", "Argos: …"]]}
    """
  end

  @doc "A reply as a batch: `{:ok, lines}` with what is well-formed in it, `:error` when nothing is."
  @spec parse(String.t()) :: {:ok, map()} | :error
  def parse(out) do
    with [json] <- Regex.run(~r/\{.*\}/s, out),
         {:ok, %{} = map} <- JSON.decode(json),
         lines = %{"Nina" => pet(map["Nina"]), "Argos" => pet(map["Argos"]), "duo" => duo(map["duo"])},
         true <- lines["Nina"] != %{} or lines["Argos"] != %{} do
      {:ok, lines}
    else
      _ -> :error
    end
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:voices, now, cast}, _from, state) do
    state =
      if cast == state.cast,
        do: state,
        else: %{state | cast: cast, lines: %{}, at: nil, key: nil, writing: nil}

    status = Home.status(now)
    key = {Enum.map(status.open, & &1.id), status.done_week}
    age = state.at && DateTime.diff(now, state.at)
    stale = age == nil or age >= @every_s or (key != state.key and age >= @changed_s)

    if stale and state.writing == nil do
      ref = make_ref()
      write(ref, prompt(scene(status, Server.Office.Weather.now(), now), cast))
      {:reply, state.lines, %{state | writing: ref, key: key, asked: now}}
    else
      {:reply, state.lines, state}
    end
  end

  @impl true
  def handle_cast({:wrote, ref, {:ok, lines}}, %{writing: ref} = state),
    do: {:noreply, %{state | lines: lines, at: state.asked, writing: nil}}

  def handle_cast({:wrote, ref, :error}, %{writing: ref} = state),
    do: {:noreply, %{state | at: state.asked, writing: nil}}

  def handle_cast({:wrote, _ref, _result}, state), do: {:noreply, state}

  defp write(ref, prompt) do
    writer = Application.get_env(:server, :home_pets_writer, &ask/1)

    Task.start(fn ->
      result =
        case writer.(prompt) do
          {:ok, out} -> parse(out)
          _ -> :error
        end

      GenServer.cast(__MODULE__, {:wrote, ref, result})
    end)
  end

  defp describe(:nina, cast) when cast == @defaults, do: @nina
  defp describe(:argos, cast) when cast == @defaults, do: @argos

  defp describe(role, cast) do
    pet = Map.fetch!(cast, role)
    other = Map.fetch!(cast, if(role == :nina, do: :argos, else: :nina))

    "called #{pet.name}, #{animal(pet)}. Let the animal show naturally. Shares the house with " <>
      "#{other.name}, #{animal(other)}.\n#{Map.fetch!(@sketches, pet.personality)}"
  end

  defp animal(%{species: species}) do
    article = if String.starts_with?(species, ["a", "e", "i", "o", "u"]), do: "an", else: "a"
    "#{article} #{species}"
  end

  defp duo_voices(cast) when cast == @defaults, do: "she is quick, he is lost."
  defp duo_voices(_cast), do: "each speaks in their own character as described above."

  defp naming(cast) when cast == @defaults, do: ""

  defp naming(%{nina: nina, argos: argos}) do
    """

    NINA is called #{nina.name} and ARGOS is called #{argos.name}. Inside the text of a line they may
    call each other, and the boss, by these names. The JSON keys and the "Nina: " / "Argos: " turn
    prefixes stay exactly as written below, whatever the names.
    """
  end

  defp name(value, default) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed =~ ~r/\A[\p{L}0-9 '-]{1,24}\z/u, do: trimmed, else: default
  end

  defp name(_, default), do: default

  defp species(value, default) when is_binary(value) do
    if value =~ ~r/\A[a-z]{1,16}\z/, do: value, else: default
  end

  defp species(_, default), do: default

  defp personality(value, default) when is_binary(value) do
    if is_map_key(@sketches, value), do: value, else: default
  end

  defp personality(_, default), do: default

  defp ask(prompt) do
    Server.ModelCli.prompt(prompt, :home_reader_cmd, :home_reader_model, {"claude", "haiku"},
      timeout_s: 120,
      tools: "",
      settings: "user"
    )
  end

  defp weather(%{desc: desc, temp_c: temp}), do: " Outside: #{desc}, #{temp}°C."
  defp weather(_none), do: ""

  defp things([], _now), do: "nothing."

  defp things(open, now) do
    Enum.map_join(open, "; ", fn row ->
      "#{row.text} (#{row.kind}, said #{DateTime.diff(now, row.since, :day)} days ago)"
    end)
  end

  defp coming([]), do: "nothing."
  defp coming(rows), do: rows |> Enum.take(5) |> Enum.map_join("; ", &"#{&1.text} (#{Clock.say(&1.due_at)})")

  defp pet(%{} = by_occasion) do
    names = Enum.map(@occasions, &elem(&1, 0))

    for {name, lines} when is_list(lines) <- by_occasion, name in names, kept = said(lines), kept != [], into: %{} do
      {name, kept}
    end
  end

  defp pet(_), do: %{}

  defp duo(chats) when is_list(chats) do
    for chat when is_list(chat) <- chats, turns = said(chat), length(turns) >= 2, do: turns
  end

  defp duo(_), do: []

  defp said(lines),
    do: for(l when is_binary(l) <- lines, l = String.trim(l), l != "" and String.length(l) <= @max + 20, do: l)
end
