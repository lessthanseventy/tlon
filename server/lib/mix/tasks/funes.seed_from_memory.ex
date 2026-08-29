defmodule Mix.Tasks.Server.SeedFromMemory do
  @shortdoc "Seed the forgetting engine from a directory of Claude memory .md files"

  @moduledoc """
  #{@shortdoc}.

  The dogfood corpus for forget-at-recall: import a directory of Claude auto-memory files (each a
  markdown doc with `name` / `description` / `metadata.type` frontmatter and a body) as server FACTS,
  so the recall read path has a real, meaningful, over-budget corpus to rank and forget — the memory
  ABOUT building server, living inside server.

  Exercises every axis the engine reads:

    * **relevance** — each fact is embedded via ollama (`Recall.embed_fact/1`), so a query ranks by
      semantic cosine (blended with keyword FTS).
    * **strength** — `created_at` is backdated to the memory's own date (strength halves every ~14d,
      so older memory is weaker), and high-signal facts get synthesized `cited` touches on top.
    * **certainty** — the type→provenance map splits `stated` (floor) from `derived` (perishable).
    * **budget** — ~30 meaty facts overflow the 4000-token working set, so recall must drop the
      low-signal/old ones from CONTEXT (never off disk — `get_facts` still returns them all).

  Type → (kind, provenance):

    * `feedback`, `user` → `constraint` / `stated` — the ALWAYS-LOADED pinned set (every thread sees them)
    * `project`          → `decision`   / `derived` — thread-scoped, forgettable
    * `reference`, other → `learned`    / `derived` — thread-scoped, forgettable

  Usage:

      mix server.seed_from_memory <memory-dir> [--thread ID] [--reset] [--drop-threads 2,3]

  `--reset` deletes every habit and (with `--drop-threads`) the listed threads + their
  messages/events/facts, keeping the target thread — the "selective clear". The memory dir may also
  come from `$TLON_SEED_MEMORY_DIR`. Idempotent per run only in that it always REPLACES the target
  thread's imported facts first, so a re-run reflects the current files rather than duplicating.

  Dev-only: hits the live DB and live ollama, writes raw `created_at` (why it lives in server, not
  console — console's boundary allows only the public API). A fact the embedder can't reach is left
  NULL (recall falls back to keyword), counted, never fatal.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  import Ecto.Query

  alias Ecto.Changeset
  alias Server.Event
  alias Server.Fact
  alias Server.Recall
  alias Server.Repo
  alias Server.Thread

  @switches [thread: :integer, reset: :boolean, drop_threads: :string]

  # Citations per type — a genuinely-useful fact stays warm despite age. Feedback/user (how to work,
  # who the user is) are cited most; references least. Deliberately coarse; calibrate from real use.
  @cites %{"feedback" => 3, "user" => 3, "project" => 1, "reference" => 0, "other" => 0}

  # Body excerpt cap (chars) so one giant memory (the 50k stage log) can't swamp the token budget.
  @excerpt 500

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")
    {opts, rest, _} = OptionParser.parse(argv, switches: @switches)

    dir =
      List.first(rest) || System.get_env("TLON_SEED_MEMORY_DIR") ||
        Mix.raise("give a memory dir (or set TLON_SEED_MEMORY_DIR)")

    thread_id = opts[:thread] || 1
    thread = Repo.get(Thread, thread_id) || Mix.raise("thread ##{thread_id} not found — open it first")

    if opts[:reset], do: reset(drop_threads(opts), thread_id)
    replace_imported(thread_id)

    files = dir |> Path.join("*.md") |> Path.wildcard() |> Enum.reject(&(Path.basename(&1) == "MEMORY.md"))
    Mix.shell().info("seeding #{length(files)} memory file(s) onto thread ##{thread_id} (#{thread.title})")

    {ok, embedded, failed} =
      Enum.reduce(files, {0, 0, 0}, fn path, {ok, emb, failed} ->
        case seed_one(path, thread_id) do
          {:ok, :embedded} -> {ok + 1, emb + 1, failed}
          {:ok, :no_vector} -> {ok + 1, emb, failed + 1}
          :skip -> {ok, emb, failed}
        end
      end)

    Mix.shell().info("seeded #{ok} fact(s): #{embedded} embedded, #{failed} left NULL (keyword-only)")
  end

  # --- one file -> one fact (+ backdate + touches + embed) ---

  defp seed_one(path, thread_id) do
    {meta, body} = parse(File.read!(path))
    type = meta["type"] || "other"
    {kind, provenance} = classify(type)
    text = fact_text(meta, body)
    at = memory_date(meta, body) || file_date(path)

    case insert_fact(thread_id, kind, provenance, text, at) do
      {:ok, fact} ->
        cite(fact, Map.get(@cites, type, 0), at)
        {:ok, embed(fact)}

      {:error, cs} ->
        Mix.shell().info("  skip #{Path.basename(path)}: #{inspect(cs.errors)}")
        :skip
    end
  end

  defp insert_fact(thread_id, kind, provenance, text, at) do
    %{thread_id: thread_id, kind: kind, text: text, provenance: provenance}
    |> Fact.bank_changeset()
    |> Changeset.force_change(:created_at, at)
    |> Repo.insert()
  end

  # Synthesize `n` cited touches, spread across the days since birth, so a warm fact ranks up.
  defp cite(_fact, 0, _at), do: :ok

  defp cite(%Fact{id: id, thread_id: tid}, n, birth) do
    span = max(DateTime.diff(DateTime.utc_now(), birth, :second), 1)

    for i <- 1..n do
      at = DateTime.shift(birth, second: div(span * i, n + 1))

      %{thread_id: tid, kind: "cited", correlation: "fact:#{id}"}
      |> Event.record_changeset()
      |> Changeset.force_change(:created_at, at)
      |> Repo.insert!()
    end
  end

  defp embed(fact) do
    case Recall.embed_fact(fact) do
      {:ok, _} -> :embedded
      {:error, _} -> :no_vector
    end
  end

  # --- selective clear ---

  defp reset(drop, keep) do
    Repo.delete_all(Server.Habit)
    kill = Enum.reject(drop, &(&1 == keep))

    for tid <- kill do
      # Every table with a thread FK must go before the thread (foreign_keys: :on).
      for schema <- [Fact, Event, Server.Message, Server.Session, Server.Todo, Server.Issue, Server.Question] do
        Repo.delete_all(from r in schema, where: r.thread_id == ^tid)
      end

      Repo.delete_all(from t in Thread, where: t.id == ^tid)
    end

    Mix.shell().info("reset: cleared habits" <> if(kill == [], do: "", else: ", dropped threads #{Enum.join(kill, ",")}"))
  end

  # Clear a prior import so a re-run reflects the current files: drop this thread's facts + their
  # citation touches (correlation `fact:<id>`), leaving messages/other events intact.
  defp replace_imported(thread_id) do
    ids = Repo.all(from f in Fact, where: f.thread_id == ^thread_id, select: f.id)

    if ids != [] do
      corrs = Enum.map(ids, &"fact:#{&1}")
      Repo.delete_all(from e in Event, where: e.correlation in ^corrs)
      Repo.delete_all(from f in Fact, where: f.id in ^ids)
    end
  end

  # --- parsing ---

  defp classify("feedback"), do: {"constraint", "stated"}
  defp classify("user"), do: {"constraint", "stated"}
  defp classify("project"), do: {"decision", "derived"}
  defp classify(_), do: {"learned", "derived"}

  # Fact text: the one-line description (the recall hook) + a body excerpt for semantic substance.
  defp fact_text(meta, body) do
    desc = meta["description"]
    excerpt = body |> String.trim() |> String.slice(0, @excerpt)
    [desc, excerpt] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("\n\n")
  end

  # Split `--- frontmatter --- body`. Frontmatter is shallow: `key: value` and a nested
  # `metadata:` block whose `type:` we lift to a flat "type" key. Good enough for these files.
  defp parse("---\n" <> rest) do
    case String.split(rest, "\n---", parts: 2) do
      [fm, body] -> {parse_frontmatter(fm), body}
      [body] -> {%{}, body}
    end
  end

  defp parse(body), do: {%{}, body}

  defp parse_frontmatter(fm) do
    fm
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\s*(\w+):\s*(.*)$/, line) do
        [_, "type", v] -> Map.put(acc, "type", unquote_val(v))
        [_, k, v] when v != "" -> Map.put_new(acc, k, unquote_val(v))
        _ -> acc
      end
    end)
  end

  defp unquote_val(v), do: v |> String.trim() |> String.trim("\"")

  # The memory's own date (first YYYY-MM-DD in the description/body), as a UTC datetime at noon.
  defp memory_date(meta, body) do
    text = "#{meta["description"]} #{body}"

    with [_, y, m, d] <- Regex.run(~r/(\d{4})-(\d{2})-(\d{2})/, text),
         {:ok, date} <- Date.new(String.to_integer(y), String.to_integer(m), String.to_integer(d)),
         {:ok, dt} <- DateTime.new(date, ~T[12:00:00], "Etc/UTC") do
      DateTime.truncate(dt, :second)
    else
      _ -> nil
    end
  end

  defp file_date(path) do
    DateTime.from_unix!(File.stat!(path, time: :posix).mtime)
  end

  defp drop_threads(opts) do
    (opts[:drop_threads] || "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.to_integer(String.trim(&1)))
  end
end
