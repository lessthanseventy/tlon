# The LongMemEval harness's door into this server's recall: one JSON request per stdin line, one
# `@@TLON <json>` reply per stdout line (the marker, because dev Logger/Ecto also write to stdout).
# Run from server/ with TLON_DATABASE naming a *_bench db (default tlon_bench). TLON_BENCH_MODE picks what is measured:
#   messages — raw session turns ranked by Server.Search.history (the episodic channel); with
#              TLON_BENCH_AROUND=n, each hit's exchange, cut to the recall token budget. Messages are
#              embedded as on write (TLON_BENCH_EMBED=0 for keyword alone)
#   facts    — Server.Memory.TurnPass extracts facts per ≤20-message chunk, ranked by Server.Recall
import Ecto.Query

alias Server.Fact
alias Server.Memory.TurnPass
alias Server.Message
alias Server.Recall
alias Server.Repo
alias Server.Search
alias Server.Thread

db = Repo.config()[:database]

unless is_binary(db) and String.ends_with?(db, "_bench"),
  do: raise("bench wipes its database on every question; refusing #{inspect(db)} — set TLON_DATABASE=tlon_bench")

mode = System.get_env("TLON_BENCH_MODE", "messages")
embed? = System.get_env("TLON_BENCH_EMBED", "1") == "1"
Logger.configure(level: :warning)
Application.put_env(:server, :memory_extractor_cmd, System.get_env("TLON_BENCH_EXTRACTOR_CMD", "pi"))
Application.put_env(:server, :memory_extractor_model, System.get_env("TLON_BENCH_EXTRACTOR_MODEL", "ollama-cloud/deepseek-v4.1-flash"))

at = fn
  nil -> DateTime.utc_now() |> DateTime.truncate(:second)
  iso -> iso |> DateTime.from_iso8601() |> elem(1) |> DateTime.truncate(:second)
end

# Only one question's haystack is ever in the database, so the server's global search is that
# question's search — the harness finishes a question before ingesting the next.
ingest = fn %{"unit" => unit, "docs" => docs} ->
  Repo.query!("TRUNCATE message, fact, thread RESTART IDENTITY CASCADE")
  thread = Repo.insert!(%Thread{title: "longmemeval #{unit}", created_at: at.(nil)})

  for doc <- Enum.sort_by(docs, &(&1["timestamp"] || "")),
      chunk <- Enum.chunk_every(Enum.reject(doc["messages"], &(&1["content"] in [nil, ""])), 20) do
    inserted =
      for m <- chunk do
        Repo.insert!(%Message{
          thread_id: thread.id,
          author: m["role"],
          body: m["content"],
          created_at: at.(doc["timestamp"]),
          payload: %{"session" => doc["id"]}
        })
      end

    # What Channel.post's embed-on-write does, awaited here so the question sees every vector.
    if embed?,
      do: inserted |> Task.async_stream(&Recall.embed_message/1, max_concurrency: 8, timeout: 60_000) |> Stream.run()

    if mode == "facts", do: TurnPass.run(thread.id, min_messages: 1)
  end

  %{"thread" => thread.id, "facts" => Repo.aggregate(Fact, :count)}
end

around = String.to_integer(System.get_env("TLON_BENCH_AROUND", "0"))
budget = get_in(Application.get_env(:server, :recall, []), [:budget]) || 4000
line = fn m -> "[#{DateTime.to_date(Map.get(m, :created_at) || m.at)}] #{m.author}: #{m.body}" end

retrieve = fn %{"query" => query, "k" => k} ->
  hits =
    case mode do
      "messages" when around == 0 ->
        for %{message_id: id} <- Search.history(query, k).shown do
          m = Repo.get!(Message, id)
          %{"id" => m.payload["session"], "text" => line.(m)}
        end

      # Each hit's exchange, in rank order, each message once, cut to the recall budget the way
      # Server.Recall cuts facts: one that does not fit is skipped and a smaller one can still land.
      "messages" ->
        {docs, _seen, _left} =
          Enum.reduce(Search.history(query, k, around: around).shown, {[], MapSet.new(), budget}, fn hit, {docs, seen, left} ->
            fresh = Enum.reject(hit.window, &MapSet.member?(seen, &1.message_id))
            text = Enum.map_join(fresh, "\n", line)
            tokens = div(String.length(text), 4)

            if fresh == [] or tokens > left do
              {docs, seen, left}
            else
              session = Repo.get!(Message, hit.message_id).payload["session"]
              {[%{"id" => session, "text" => text} | docs], MapSet.union(seen, MapSet.new(fresh, & &1.message_id)), left - tokens}
            end
          end)

        Enum.reverse(docs)

      "facts" ->
        thread = Repo.one!(from(t in Thread, limit: 1))

        for %{fact: f} <- Recall.working_set_for_thread(thread, query: query, include_pinned: false) do
          %{"id" => "fact-#{f.id}", "text" => "[#{f.kind}] #{f.text}"}
        end
    end

  %{"hits" => hits}
end

:stdio
|> IO.stream(:line)
|> Enum.each(fn line ->
  req = JSON.decode!(line)

  reply =
    try do
      case req["op"] do
        "ingest" -> ingest.(req)
        "retrieve" -> retrieve.(req)
        "ping" -> %{"mode" => mode, "database" => db}
      end
    rescue
      e -> %{"error" => Exception.format(:error, e, __STACKTRACE__)}
    end

  IO.puts("@@TLON " <> JSON.encode!(reply))
end)
