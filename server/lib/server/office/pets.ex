defmodule Server.Office.Pets do
  @moduledoc """
  The pets' voices: what Nina and Argos say, written in each one's personality by the cheap model
  tier (`Server.ModelCli`, banter's `:banter_cmd`/`:banter_model`) — a personality, not a script.

  An office reacts to its pets instantly (a pat cannot wait on a model), so this does not write one
  line at a time: it writes a batch per pet, a few lines for each OCCASION (`occasions/1`: patted,
  woken, a coworker starting a test, a treat…), about this office as it is now (`Banter.scene/1`), and
  the office picks from the batch as things happen; a line about a coworker carries `{name}` for the
  office to fill in. Lazy like banter: a batch is only written while an office asks (`voices/1`), at
  most one per pet per workspace every `@every_s`. On with banter (`TLON_BANTER=1`). A reply that does
  not parse is dropped, and the last good batch stands.
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
  @tools ~w(read edit bash search web test delegate)
  @fusses %{
    "fuss_pat" => "{name}, a coworker, gives a pat on the head",
    "fuss_scratch" => "{name} gives a good scratch behind the ears",
    "fuss_belly" => "{name} goes for a belly rub",
    "fuss_treat" => "{name} tosses over a treat"
  }

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Each pet's lines for this workspace, by name then occasion — `%{"Nina" => %{"pet" => [line]}}` —
  and, when a pet's batch is stale, a new one asked for in the background. `%{}` where this is off.
  """
  @spec voices(integer()) :: %{String.t() => %{String.t() => [String.t()]}}
  def voices(workspace_id) do
    if GenServer.whereis(__MODULE__), do: GenServer.call(__MODULE__, {:voices, workspace_id}), else: %{}
  end

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

  @doc "What `pet` is asked: its personality, the office (`ctx` as `Banter.context/1` gives it), its occasions."
  def prompt(pet, ctx) do
    asks = Enum.map_join(occasions(pet), "\n", fn {k, what} -> ~s(- "#{k}": #{what}) end)

    """
    You write the lines of #{pet}, a pet in a pixel-art office of AI coworkers; each line is said
    out loud in a speech balloon over the pet.
    WHO #{String.upcase(pet)} IS: #{@pets[pet]}
    #{Banter.scene(ctx)}

    For EACH occasion below write 3 different lines, each under 60 characters, in character and
    funny; vary them. Where a line is about a coworker, write {name} for them, or use the names
    above; a coworker is "they", never "he" or "she". No emoji, never cruel. Respond with ONLY a
    JSON object:
    {"lines": {"<occasion>": ["...", "...", "..."], ...}}
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

  defp clean(lines), do: for(l <- lines, is_binary(l), l = String.trim(l), l != "", do: String.slice(l, 0, 90))

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:voices, ws}, _from, state) do
    now = System.system_time(:second)
    %{voices: voices, at: at} = Map.get(state, ws, %{voices: %{}, at: 0})

    if now - at >= @every_s, do: ask(ws)

    {:reply, voices, Map.put(state, ws, %{voices: voices, at: if(now - at >= @every_s, do: now, else: at)})}
  end

  @impl true
  def handle_cast({:wrote, _ws, _pet, nil}, state), do: {:noreply, state}

  def handle_cast({:wrote, ws, pet, lines}, state) do
    entry = Map.get(state, ws, %{voices: %{}, at: 0})
    {:noreply, Map.put(state, ws, put_in(entry.voices[pet], lines))}
  end

  defp ask(ws) do
    me = self()

    for pet <- Map.keys(@pets) do
      Task.Supervisor.start_child(Server.TaskSupervisor, fn -> GenServer.cast(me, {:wrote, ws, pet, write(ws, pet)}) end)
    end
  end

  defp write(ws, pet) do
    with {:ok, out} <-
           Server.ModelCli.prompt(
             prompt(pet, Banter.context(ws)),
             :banter_cmd,
             :banter_model,
             {"pi", "ollama-cloud/deepseek-v4.1-flash"}
           ),
         %{} = lines when map_size(lines) > 0 <- parse(out, pet) do
      lines
    else
      _ -> nil
    end
  end
end
