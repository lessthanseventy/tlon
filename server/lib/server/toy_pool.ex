defmodule Server.ToyPool do
  @moduledoc """
  The toy's generated pools, per workspace, written by `Server.Generator` and stored in `toy_pool`:
  doorbell visitors (name, look seed, one line), each seat's in-voice reaction lines per event, and
  pun/joke ideas for the canvas brief (and the part library kept by `Server.GeneratedParts`), refilled daily by `refresh_cli/0` (the `toys:refresh`
  task, a script schedule). Every read is the stored pool or `[]` — the render path never calls the
  model, and a caller with `[]` uses its handwritten lines.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Server.{Generator, Persona, Repo}

  @events ~w(zoo meteor fire_drill power_cut duck)
  # under a day, so a daily run whose last one finished a little later still refills
  @fresh_hours 20
  @timeout_streak 3

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
  either crew, then the day's invented accessory (`Server.GeneratedParts`). `[{kind, result}]`, ending
  in `{:stopped, untried}` when #{@timeout_streak} model timeouts in a row stopped the run.
  """
  def refresh_all_due(ws) do
    {results, stop} = run_jobs(jobs(ws), fn _ -> :ok end)
    Enum.map(results, fn {_ws, kind, res} -> {kind, res} end) ++ if(stop, do: [{:stopped, stop}], else: [])
  end

  @doc """
  The `toys:refresh` run over every staffed workspace: each pool's result is printed as it lands, and
  the run stops after #{@timeout_streak} model timeouts in a row (a hung CLI answers the rest no
  better). Raises when a pool failed or the run stopped.
  """
  def refresh_cli do
    jobs = for %{id: ws} <- Server.Workspaces.all(), Server.Workspaces.bench_all(ws) != [], job <- jobs(ws), do: job
    {results, stop} = run_jobs(jobs, &IO.puts/1)

    fresh = Enum.count(results, &match?({_, _, {:ok, _}}, &1))
    off = Enum.count(results, &match?({_, _, {:error, :off}}, &1))
    bad = length(results) - fresh - off

    IO.puts("toys: #{fresh} of #{length(jobs)} pools fresh#{if off > 0, do: " (banter is off)"}")
    if stop, do: IO.puts("stopped after #{@timeout_streak} model timeouts in a row; #{stop} pools not tried")
    if bad > 0 or stop, do: raise("refused")
    :ok
  end

  # One pool at a time: a CLI that hangs costs its timeout per call, so the run gives up after a streak
  # of them. `out` hears each pool's line as it lands. `{results, untried | nil}`.
  defp run_jobs(jobs, out, streak \\ 0, acc \\ [])
  defp run_jobs([], _out, _streak, acc), do: {Enum.reverse(acc), nil}
  defp run_jobs(jobs, _out, @timeout_streak, acc), do: {Enum.reverse(acc), length(jobs)}

  defp run_jobs([{ws, kind} | rest], out, streak, acc) do
    res = job(ws, kind)
    out.(line(ws, kind, res))
    streak = if match?({:error, {:model_cli_timeout, _, _}}, res), do: streak + 1, else: 0
    run_jobs(rest, out, streak, [{ws, kind, res} | acc])
  end

  defp jobs(ws) do
    seats = for %{name: name} <- Server.Workspaces.bench_all(ws), do: {:reactions, name}
    for kind <- [:visitors, :puns | seats] ++ [:part], do: {ws, kind}
  end

  defp job(ws, :part), do: Server.GeneratedParts.refresh_due(ws)
  defp job(ws, kind), do: refresh_due(ws, kind)

  defp line(ws, kind, {:ok, _}), do: "##{ws} #{inspect(kind)}: fresh"
  defp line(ws, kind, {:error, why}), do: "##{ws} #{inspect(kind)}: #{inspect(why)}"

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

  @doc """
  Everything stored for `ws` in one read, for the office to show: `%{visitors, puns, reactions, parts}`,
  `reactions` being `%{seat => %{event => [line]}}`, `parts` the invented-accessory library
  (`Server.GeneratedParts.library/1`). Empty parts are `[]` / `%{}` until generated.
  """
  def day(ws) do
    reactions =
      Map.new(
        Repo.all(
          from(p in __MODULE__,
            where: p.workspace_id == ^ws and like(p.key, "reactions:%"),
            select: {p.key, p.items}
          )
        ),
        fn {"reactions:" <> seat, %{"items" => by_event}} -> {seat, by_event} end
      )

    %{visitors: visitors(ws), puns: puns(ws), reactions: reactions, parts: Server.GeneratedParts.library(ws)}
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
       %{"reactions" => %{} = r} ->
         reactions =
           Map.new(
             for e <- @events, is_list(r[e]), lines = Enum.filter(r[e], &is_binary/1), lines != [], do: {e, lines}
           )

         if reactions != %{}, do: reactions

       _ ->
         nil
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
