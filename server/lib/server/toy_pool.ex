defmodule Server.ToyPool do
  @moduledoc """
  The toy's generated pools, per workspace, written by `Server.Generator` and stored in `toy_pool`:
  doorbell visitors (name, look seed, one line), each seat's in-voice reaction lines per event, and
  pun/joke ideas for the canvas brief, refilled daily by `refresh_all_due/1` (the `toys:refresh`
  task, a script schedule). Every read is the stored pool or `[]` — the render path never calls the
  model, and a caller with `[]` uses its handwritten lines.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.{Generator, Persona, Repo}

  @events ~w(zoo meteor fire_drill power_cut duck)
  # under a day, so a daily run whose last one finished a little later still refills
  @fresh_hours 20

  schema "toy_pool" do
    field :workspace_id, :integer
    field :key, :string
    field :items, :map
    field :seed, :integer
    field :generated_at, :utc_datetime
  end

  @doc ~s(The doorbell visitors, `[%{"name", "look_seed", "line"}]`.)
  def visitors(ws), do: read(ws, "visitors") || []

  @doc "Pun and joke ideas, `[String.t()]`."
  def puns(ws), do: read(ws, "puns") || []

  @doc "What `seat` says at `event`, in voice: `[String.t()]`, `[]` until generated."
  def reactions(ws, seat, event), do: (read(ws, "reactions:#{seat}") || %{})[event] || []

  @doc "Generate the pool afresh (`:visitors`, `:puns` or `{:reactions, seat}`) and store it."
  def refresh(ws, kind, opts \\ []) do
    seed = opts[:seed] || :rand.uniform(1_000_000)
    {key, prompt, shape} = spec(ws, kind, seed)

    with {:ok, out} <- Generator.run(prompt),
         items when not is_nil(items) <- Server.JsonBlob.first_valid(out, shape) do
      row = %__MODULE__{workspace_id: ws, key: key, items: %{"items" => items}, seed: seed, generated_at: now()}

      Repo.insert!(row,
        on_conflict: {:replace, [:items, :seed, :generated_at]},
        conflict_target: [:workspace_id, :key]
      )

      {:ok, items}
    else
      nil -> {:error, :unparsed}
      {:error, _} = e -> e
    end
  end

  @doc """
  `refresh_due/2` for every pool of `ws`: visitors, puns, and the reactions of each seat on its bench,
  either crew. `[{kind, result}]`.
  """
  def refresh_all_due(ws) do
    seats = for %{name: name} <- Server.Workspaces.bench_all(ws), do: {:reactions, name}
    for kind <- [:visitors, :puns | seats], do: {kind, refresh_due(ws, kind)}
  end

  @doc "`refresh/3` unless the pool was written in the last #{@fresh_hours} hours."
  def refresh_due(ws, kind) do
    {key, _, _} = spec(ws, kind, 0)

    case Repo.get_by(__MODULE__, workspace_id: ws, key: key) do
      %{generated_at: at, items: %{"items" => items}} ->
        if DateTime.diff(now(), at, :hour) < @fresh_hours, do: {:ok, items}, else: refresh(ws, kind)

      nil ->
        refresh(ws, kind)
    end
  end

  @doc false
  def age!(ws, kind, days) do
    {key, _, _} = spec(ws, kind, 0)
    at = DateTime.add(now(), -days * 86_400)
    Repo.update_all(from(p in __MODULE__, where: p.workspace_id == ^ws and p.key == ^key), set: [generated_at: at])
  end

  defp read(ws, key) do
    case Repo.get_by(__MODULE__, workspace_id: ws, key: key) do
      %{items: %{"items" => items}} -> items
      nil -> nil
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  defp spec(_ws, :visitors, seed) do
    {"visitors",
     intro(seed) <>
       ~s(Invent 5 visitors who ring the doorbell: JSON {"visitors": [{"name": "", "look_seed": <int>, "line": "<what they say at the door, under 80 chars>"}]}),
     fn d -> list("visitors", d, &visitor?/1) end}
  end

  defp spec(_ws, :puns, seed) do
    {"puns", intro(seed) <> ~s(Write 8 short puns or nerdy programming jokes: JSON {"puns": ["", …]}),
     fn d -> list("puns", d, &is_binary/1) end}
  end

  defp spec(ws, {:reactions, seat}, seed) do
    voice = (Persona.get(ws, seat) || %{})["voice"] || ""

    prompt =
      intro(seed) <>
        "#{seat} talks like this: #{voice}. For each event (#{Enum.join(@events, ", ")}) write 2 short in-voice lines they say as it happens: " <>
        ~s(JSON {"reactions": {"zoo": ["", ""], …}})

    {"reactions:#{seat}", prompt,
     fn
       %{"reactions" => %{} = r} -> Map.new(for e <- @events, is_list(r[e]), do: {e, Enum.filter(r[e], &is_binary/1)})
       _ -> nil
     end}
  end

  defp intro(seed),
    do: "You write material for a pixel-art office of AI coworkers. Warm, dry, never cruel. Seed: #{seed}\n"

  defp list(key, decoded, ok?) do
    with %{^key => [_ | _] = l} <- decoded, true <- Enum.all?(l, ok?), do: l, else: (_ -> nil)
  end

  defp visitor?(%{"name" => n, "look_seed" => s, "line" => l}), do: is_binary(n) and is_integer(s) and is_binary(l)
  defp visitor?(_), do: false
end
