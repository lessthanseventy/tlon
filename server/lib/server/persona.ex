defmodule Server.Persona do
  @moduledoc """
  A seat's persona: a short backstory, four quirks (desk object, hobby, catchphrase, pet peeve) and
  a voice line, stored as JSON on the `workspace_agent` row beside the `seed` that drew it. Voice
  only, never a different decision (toy design §2).

  Written by the cheap model tier (`Server.ModelCli`; `config :server, generator_cmd:,
  generator_model:`, default `pi` on `ollama-cloud/deepseek-v4.1-flash`, the flat ollama bucket)
  at hire or on `tlon-cli persona <name> [--reroll]` — never on a render path: `get/2` only reads.

  The seed is the whole draw: it picks the quirk themes handed to the model and, with no model, the
  fallback's backstory and quirks, so one seed always asks the same question. A call is made only
  while banter is on and fewer than `:generator_daily_cap` (default 50) were made today; otherwise,
  and when a call fails or its reply does not parse, the seat gets the handwritten fallback (the §2
  voice table, `"source" => "fallback"`).
  """
  import Ecto.Query

  alias Server.{Repo, WorkspaceAgent}

  @cap 50
  @default {"pi", "ollama-cloud/deepseek-v4.1-flash"}

  @voices %{
    "scharlach" => "crisp and slightly too formal; enforces the rules and enjoys it too much",
    "tertius" => "dry, unflappable, has seen it all",
    "hronir" => "old-school; mutters about how it was done before",
    "lonnrot" => "a detective; reviews read like case notes",
    "yu" => "careful, precise, a little anxious",
    "beatriz" => "brisk, organized, has a spreadsheet for this",
    "nolan" => ~s(theatrical; QA is "the performance"),
    "emma" => "quietly determined; finishes what she starts",
    "ireneo" => "remembers everything, says so",
    "daneri" => "grandiose; every change is a masterpiece",
    "sonny" => "sunny; brings a flower to every handoff"
  }
  @archetype_voices %{
    "builder" => "plain-spoken; says what was built and moves on",
    "reviewer" => "measured; every note comes with a reason",
    "manager" => "even-tempered; keeps everyone pointed the same way"
  }
  @generic_voice "friendly and brief"

  @desk ["a chipped mug", "a rubber duck", "a small cactus", "a stack of index cards", "a brass bell"]
  @hobbies ["birdwatching", "crosswords", "pickling", "model trains", "chess by post"]
  @phrases ["Well, there it is.", "Noted.", "Funny, that.", "Back in a minute.", "Right then."]
  @peeves ["unlabelled boxes", "loud keyboards", "meetings with no agenda", "tabs left open", "loose ends"]
  @origins [
    "grew up above a clockmaker's shop",
    "learned the trade from a night-shift librarian",
    "came to the office by a long way round",
    "once fixed the whole building's clock by accident"
  ]

  @doc "The seat's stored persona, or nil. A read: never a model call."
  @spec get(integer(), String.t()) :: map() | nil
  def get(workspace_id, name) do
    case seat(workspace_id, name) do
      {_agent, row} -> row.persona
      nil -> nil
    end
  end

  @doc "The stored persona, generated first when the seat has none."
  @spec ensure(integer(), String.t()) :: {:ok, map()} | {:error, :no_seat}
  def ensure(workspace_id, name) do
    case seat(workspace_id, name) do
      nil -> {:error, :no_seat}
      {_agent, %{persona: %{} = p}} -> {:ok, p}
      {_agent, _row} -> generate(workspace_id, name)
    end
  end

  @doc "Generate afresh from a new random seed (different from the stored one) and store it."
  @spec reroll(integer(), String.t()) :: {:ok, map()} | {:error, :no_seat}
  def reroll(workspace_id, name) do
    old = get(workspace_id, name)
    seed = Enum.find(Stream.repeatedly(fn -> :rand.uniform(1_000_000) end), &(&1 != (old && old["seed"])))
    generate(workspace_id, name, seed: seed)
  end

  @doc "Generate and store a persona for the seat. `opts[:seed]` makes it reproducible."
  @spec generate(integer(), String.t(), keyword()) :: {:ok, map()} | {:error, :no_seat}
  def generate(workspace_id, name, opts \\ []) do
    case seat(workspace_id, name) do
      nil ->
        {:error, :no_seat}

      {_agent, row} ->
        seed = opts[:seed] || :rand.uniform(1_000_000)
        today = Date.to_iso8601(Date.utc_today())

        persona =
          if allowed?(today), do: ask(name, row.archetype, seed, today), else: fallback(name, row.archetype, seed)

        {:ok, _} = row |> Ecto.Changeset.change(persona: persona) |> Repo.update()
        {:ok, persona}
    end
  end

  defp ask(name, archetype, seed, today) do
    prompt = """
    You write the persona of one coworker in a pixel-art office of AI coworkers. The name is
    #{name}, a #{archetype}. Their voice, to start from: #{voice(name, archetype)}.
    Seed: #{seed}
    Lean on these: desk object #{pick(@desk, seed, 0)}, hobby #{pick(@hobbies, seed, 1)}, catchphrase like
    "#{pick(@phrases, seed, 2)}", pet peeve #{pick(@peeves, seed, 3)}. Dry, warm, a little absurd; never cruel.
    Respond with ONLY a JSON object: {"backstory": "<two sentences>", "quirks": {"desk_object": "",
    "hobby": "", "catchphrase": "", "pet_peeve": ""}, "voice": "<one line on how they talk>"}
    """

    result =
      Server.ModelCli.prompt(prompt, :generator_cmd, :generator_model, @default)

    with {:ok, out} <- result, %{} = p <- parse(out) do
      Map.merge(p, %{"seed" => seed, "source" => "model", "called_on" => today})
    else
      _ -> name |> fallback(archetype, seed) |> Map.put("called_on", today)
    end
  end

  defp fallback(name, archetype, seed) do
    %{
      "seed" => seed,
      "source" => "fallback",
      "voice" => voice(name, archetype),
      "backstory" => "#{name} #{pick(@origins, seed, 4)}.",
      "quirks" => %{
        "desk_object" => pick(@desk, seed, 0),
        "hobby" => pick(@hobbies, seed, 1),
        "catchphrase" => pick(@phrases, seed, 2),
        "pet_peeve" => pick(@peeves, seed, 3)
      }
    }
  end

  @doc false
  def parse(out) do
    Server.JsonBlob.first_valid(out, fn
      %{"backstory" => b, "quirks" => %{} = q, "voice" => v} when is_binary(b) and is_binary(v) ->
        keys = ~w(desk_object hobby catchphrase pet_peeve)
        if Enum.all?(keys, &is_binary(q[&1])), do: %{"backstory" => b, "quirks" => Map.take(q, keys), "voice" => v}

      _ ->
        nil
    end)
  end

  defp voice(name, archetype), do: Map.get(@voices, name) || Map.get(@archetype_voices, archetype) || @generic_voice

  defp allowed?(today) do
    Server.OperatorConfig.banter?() and calls_on(today) < Application.get_env(:server, :generator_daily_cap, @cap)
  end

  defp calls_on(day) do
    Repo.one(from wa in WorkspaceAgent, where: fragment("?->>'called_on' = ?", wa.persona, ^day), select: count())
  end

  # the seed alone picks: each slot reads its own position, so one seed always draws the same set
  defp pick(list, seed, slot), do: Enum.at(list, rem(seed + slot * 7919, length(list)))

  defp seat(workspace_id, name) do
    Repo.one(
      from wa in WorkspaceAgent,
        join: a in Server.Agent,
        on: a.id == wa.agent_id,
        where: wa.workspace_id == ^workspace_id and a.name == ^name,
        select: {a, wa}
    )
  end
end
