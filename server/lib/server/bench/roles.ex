defmodule Server.Bench.Roles do
  @moduledoc """
  The per-role bench (`bench/roles/`, `mise run bench:roles`): can each coworker archetype, on the
  model it is routed to, do its job — and what does that cost. The pure half: the role table, the
  frozen task fixtures, the graders, the run record and the README table. The model calls are
  `Server.Bench.Roles.Runner`'s.

  A task is a directory `bench/roles/tasks/<set>/<id>/`: `prompt.md` (what the role is asked),
  `task.json` (`tier` — `canary` or `full` — and `grader`), and for a builder `repo/`, the fixture
  repo it works in. Graders:

    * `check` — `cmd` run in the workdir after the role is done, pass on exit 0. The task's
      `check/` files are copied over the workdir first: the acceptance test the role never saw,
      which it cannot pass by editing.
    * `json` — the reply's JSON object; each key of `expect` is matched with `equals`, `in` or
      `matches` (a case-insensitive regex). Every expected key must be present.
    * `judge` — `rubric` scored 1–5 per dimension by `Server.Eval.Judge`; pass at `pass` (3.5).

  The `canary` suite runs the canary tier; `full` runs every tier.
  """

  # role => the archetype it benches, the grade its model is routed by (nil: the archetype's own),
  # and the task set it answers
  @roles %{
    "builder-junior" => %{archetype: :builder, grade: "junior", set: "builder"},
    "builder-senior" => %{archetype: :builder, grade: "senior", set: "builder"},
    "reviewer" => %{archetype: :reviewer, grade: nil, set: "reviewer"},
    "planner" => %{archetype: :planner, grade: nil, set: "planner"},
    "qa" => %{archetype: :qa, grade: nil, set: "qa"},
    "manager" => %{archetype: :surveyor, grade: nil, set: "manager"},
    "librarian" => %{archetype: :librarian, grade: "senior", set: "librarian"}
  }

  @tiers ~w(canary full)
  @pass 3.5

  @doc "The role table: role name => `%{archetype, grade, set}`."
  def roles, do: @roles

  @doc "The tiers a suite runs: `canary` its own, `full` every one."
  def tiers("canary"), do: ["canary"]
  def tiers("full"), do: @tiers

  @doc """
  The model a role runs on: `override`, else its grade's (`grade_model`), else the archetype's
  default (`archetypes`), else the senior grade's for an archetype this commit doesn't have.
  """
  def model(%{archetype: a, grade: g}, override, archetypes, grade_model) do
    override || (g && grade_model.(g)) || get_in(archetypes, [a, :model]) || grade_model.("senior")
  end

  @bench_note """
  BENCH: this is a frozen benchmark task, run headless and outside any thread. The server's tools
  (post_message, submit_review, staff_child, …) are not here: do the work with the tools you have,
  and give your answer in your final reply, in exactly the format the task asks for.\
  """

  @doc """
  The argv that runs `prompt` as `profile` would: the harness's one-shot aside (its model, effort
  and persona, print mode, no saved session), the bench note appended to the persona, its
  machine-readable output on, and — for a role that writes (`write?`) — the edit and shell tools.
  """
  def argv(%Server.Profile{} = p, prompt, write?) do
    system = Enum.join(Enum.reject([p.system_prompt, @bench_note], &is_nil/1), "\n\n")
    base = Server.Harness.driver(p.harness).aside_argv(p, system, prompt)

    case p.harness do
      :claude_code ->
        tools = if write?, do: ["--allowedTools", "Edit,Write,Bash"], else: []
        swap_tools(base, write?, "Read,Grep,Glob,Edit,Write,Bash") ++ tools ++ ["--output-format", "json"]

      :pi ->
        swap_tools(base, write?, "read,grep,find,ls,edit,write,bash") ++ ["--mode", "json"]
    end
  end

  defp swap_tools(argv, false, _tools), do: argv

  defp swap_tools(argv, true, tools) do
    i = Enum.find_index(argv, &(&1 == "--tools"))
    List.replace_at(argv, i + 1, tools)
  end

  @doc "`provider/model[:effort]` → the model map; effort defaults to medium."
  def parse_model(spec) do
    case String.split(spec, "/", parts: 2) do
      [provider, rest] when provider != "" and rest != "" ->
        case String.split(rest, ":", parts: 2) do
          [m, effort] -> {:ok, %{provider: provider, model: m, thinking: effort}}
          [m] -> {:ok, %{provider: provider, model: m, thinking: "medium"}}
        end

      _ ->
        {:error, "expected provider/model[:effort], got #{inspect(spec)}"}
    end
  end

  @doc "Every task of `set` under `dir` in the suite's tiers, in id order. Raises on a malformed fixture."
  def load(dir, set, suite) do
    tiers = tiers(suite)

    dir
    |> Path.join(set)
    |> Path.join("*/task.json")
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.map(&task(&1, set))
    |> Enum.filter(&(&1.tier in tiers))
  end

  defp task(file, set) do
    dir = Path.dirname(file)
    meta = file |> File.read!() |> JSON.decode!()
    repo = Path.join(dir, "repo")

    t = %{
      id: Path.basename(dir),
      set: set,
      dir: dir,
      tier: meta["tier"],
      grader: meta["grader"],
      prompt: dir |> Path.join("prompt.md") |> File.read!(),
      repo: if(File.dir?(repo), do: repo)
    }

    if !(t.tier in @tiers and valid_grader?(t.grader)), do: raise("bench task #{set}/#{t.id}: bad task.json")
    t
  end

  defp valid_grader?(%{"kind" => "check", "cmd" => cmd}) when is_binary(cmd), do: true
  defp valid_grader?(%{"kind" => "json", "expect" => e}) when is_map(e) and map_size(e) > 0, do: true
  defp valid_grader?(%{"kind" => "judge", "rubric" => r}) when is_binary(r), do: true
  defp valid_grader?(_), do: false

  @doc """
  Grade a `json` task's reply: `%{passed, score: nil, detail}`. The object is the last fenced
  `json` block, else the first JSON object in the reply holding every expected key.
  """
  def grade_json(%{"expect" => expect}, reply) do
    case extract(reply, Map.keys(expect)) do
      nil ->
        %{passed: false, score: nil, detail: "no JSON object with #{Enum.join(Map.keys(expect), ", ")}"}

      obj ->
        misses = for {k, m} <- Enum.sort(expect), !hit?(m, obj[k]), do: "#{k}=#{inspect(obj[k])}"
        %{passed: misses == [], score: nil, detail: if(misses == [], do: "ok", else: Enum.join(misses, "; "))}
    end
  end

  defp extract(reply, keys) do
    shape = fn
      %{} = obj -> if Enum.all?(keys, &Map.has_key?(obj, &1)), do: obj
      _ -> nil
    end

    fenced =
      ~r/```json\s*\n(.*?)```/s
      |> Regex.scan(reply, capture: :all_but_first)
      |> List.last()

    (fenced && Server.JsonBlob.first_valid(hd(fenced), shape)) || Server.JsonBlob.first_valid(reply, shape)
  end

  defp hit?(%{"equals" => v}, got), do: norm(got) == norm(v)
  defp hit?(%{"in" => vs}, got), do: norm(got) in Enum.map(vs, &norm/1)
  defp hit?(%{"matches" => re}, got), do: got != nil and Regex.match?(Regex.compile!(re, "i"), text(got))

  # a model asked for null often writes it as a string
  defp norm(v) when is_binary(v) do
    v
    |> String.trim()
    |> String.downcase()
    |> case do
      s when s in ["", "null"] -> nil
      s -> s
    end
  end

  defp norm(v), do: v

  defp text(v) when is_binary(v), do: v
  defp text(v) when is_list(v), do: Enum.map_join(v, "\n", &text/1)
  defp text(v), do: JSON.encode!(v)

  @doc "The prompt the judge scores a `judge` task's reply with."
  def judge_prompt(%{"rubric" => rubric}, task_prompt, reply) do
    """
    Score how well a coworker did the task below, on the rubric's dimensions.

    RUBRIC:
    #{rubric}

    THE TASK IT WAS GIVEN:
    #{task_prompt}

    ITS REPLY:
    #{reply}
    """
  end

  @doc "A judge's `{:ok, %{scores, rationale}}` → `%{passed, score, detail}` at the grader's `pass`."
  def grade_judged(grader, {:ok, %{scores: scores, rationale: why}}) do
    score = Float.round(Enum.sum(Map.values(scores)) / map_size(scores), 2)
    %{passed: score >= (grader["pass"] || @pass), score: score, detail: why}
  end

  def grade_judged(_grader, {:error, reason}),
    do: %{passed: false, score: nil, detail: "judge failed: #{inspect(reason)}"}

  @doc """
  A harness's machine-readable stdout → `{reply, usage}`. `:claude_code` prints one JSON result
  (`--output-format json`); `:pi` prints an event per line (`--mode json`), whose assistant
  `message_end`s carry the usage. Usage is `%{input, output, cache_read, cache_write, cost_usd,
  turns}`; `cost_usd` is nil when the harness reports none.
  """
  def parse_output(:claude_code, out) do
    out
    |> String.split("\n", trim: true)
    |> Enum.reverse()
    |> Enum.find_value(&decode_result/1)
    |> case do
      nil ->
        {out, usage(%{})}

      r ->
        u = r["usage"] || %{}

        {r["result"] || "",
         usage(%{
           input: u["input_tokens"],
           output: u["output_tokens"],
           cache_read: u["cache_read_input_tokens"],
           cache_write: u["cache_creation_input_tokens"],
           cost_usd: r["total_cost_usd"],
           turns: r["num_turns"]
         })}
    end
  end

  def parse_output(:pi, out) do
    msgs =
      for line <- String.split(out, "\n", trim: true),
          {:ok, %{"type" => "message_end", "message" => %{"role" => "assistant"} = m}} <- [JSON.decode(line)],
          do: m

    reply =
      case List.last(msgs) do
        nil -> ""
        m -> Enum.join(for(%{"type" => "text", "text" => t} <- List.wrap(m["content"]), do: t))
      end

    sum = fn key -> msgs |> Enum.map(&(get_in(&1, ["usage", key]) || 0)) |> Enum.sum() end

    {reply,
     usage(%{
       input: sum.("input"),
       output: sum.("output"),
       cache_read: sum.("cacheRead"),
       cache_write: sum.("cacheWrite"),
       turns: length(msgs)
     })}
  end

  defp decode_result(line) do
    case JSON.decode(line) do
      {:ok, %{"type" => "result"} = r} -> r
      _ -> nil
    end
  end

  defp usage(u) do
    %{
      input: u[:input] || 0,
      output: u[:output] || 0,
      cache_read: u[:cache_read] || 0,
      cache_write: u[:cache_write] || 0,
      cost_usd: u[:cost_usd],
      turns: u[:turns] || 0
    }
  end

  @doc """
  One run's record: `meta` (role, archetype, grade, model, effort, harness, commit, suite,
  started_at) plus the tally of its task results — pass/total per tier, the rubric average of the
  judged tasks, wall time, and usage summed.
  """
  def record(meta, results) do
    tiers =
      for tier <- @tiers, rs = Enum.filter(results, &(&1.tier == tier)), rs != [], into: %{} do
        {tier, %{passed: Enum.count(rs, & &1.passed), total: length(rs)}}
      end

    scores = for %{score: s} <- results, s != nil, do: s
    costs = for %{usage: %{cost_usd: c}} <- results, c != nil, do: c

    Map.merge(meta, %{
      tiers: tiers,
      rubric: if(scores != [], do: Float.round(Enum.sum(scores) / length(scores), 2)),
      wall_s: results |> Enum.reduce(0.0, &(&1.wall_s + &2)) |> Float.round(1),
      calls: length(results),
      usage: %{
        input: total(results, :input) + total(results, :cache_read) + total(results, :cache_write),
        output: total(results, :output),
        cost_usd: if(costs != [], do: Float.round(Enum.sum(costs), 4))
      },
      tasks: results
    })
  end

  defp total(results, key), do: results |> Enum.map(& &1.usage[key]) |> Enum.sum()

  @doc "Add `records` to the day's results file (a JSON list), creating it."
  def append!(path, records) do
    prior = if File.exists?(path), do: path |> File.read!() |> JSON.decode!(), else: []
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode_to_iodata!(prior ++ records, pretty: true))
  end

  @doc "Every record in the results files under `dir`, newest first."
  def history(dir) do
    dir
    |> Path.join("*.json")
    |> Path.wildcard()
    |> Enum.flat_map(&(&1 |> File.read!() |> JSON.decode!()))
    |> Enum.sort_by(& &1["started_at"], :desc)
  end

  @doc "`bench/roles/README.md` from the run history (string-keyed records, newest first)."
  def readme(records) do
    rows = Enum.map_join(records, "\n", &row/1)

    """
    # Role bench

    Can each coworker archetype, on the model it is routed to, do its job — and what does it cost?
    Generated by `mise run bench:roles` from `results/*.json`; do not edit by hand.

    `mise run bench:roles -- --suite canary|full [--role R] [--model provider/model[:effort]]`.
    Roles: #{@roles |> Map.keys() |> Enum.sort() |> Enum.join(", ")}. Tasks are frozen fixtures under
    `tasks/<set>/<id>/` (`Server.Bench.Roles` documents the format). A cell is passed/total for that
    tier; *rubric* is the judged tasks' 1–5 average; *tokens* is input (cache included) / output;
    *cost* is the harness's list-price figure (Claude Code reports one; a plan bills none of it), `–`
    where the harness reports none.

    | date | role | model | effort | harness | commit | suite | canary | full | rubric | wall | tokens in/out | cost |
    |---|---|---|---|---|---|---|---|---|---|---|---|---|
    #{rows}
    """
  end

  defp row(r) do
    cells = [
      String.slice(r["started_at"] || "", 0, 10),
      r["role"],
      r["model"],
      r["effort"],
      r["harness"],
      r["commit"],
      r["suite"],
      tier_cell(r["tiers"]["canary"]),
      tier_cell(r["tiers"]["full"]),
      r["rubric"] || "–",
      "#{r["wall_s"]}s",
      "#{r["usage"]["input"]}/#{r["usage"]["output"]}",
      cost_cell(r["usage"]["cost_usd"])
    ]

    "| " <> Enum.map_join(cells, " | ", &to_string/1) <> " |"
  end

  defp tier_cell(%{"passed" => p, "total" => t}), do: "#{p}/#{t}"
  defp tier_cell(_), do: "–"

  defp cost_cell(nil), do: "–"
  defp cost_cell(c), do: "$" <> :erlang.float_to_binary(c / 1, decimals: 3)
end
