# Souls step 5 — the diary: they grow (ticket #64)

Design: `docs/plans/2026-10-08-souls-design.md` §4, §6 step 5. Check: after a merged workline, its
builder's diary mentions it. Rule bounding all of it: presentation only — the diary is read by
voice surfaces, never by a work decision.

## What exists (verified on main bd0f803)

- `Server.Soul` (`server/lib/server/soul.ex`): `dir/0`, `read/1` (`%{heading => text}`), `voice/1`,
  `tone/1`, `draft/2`. Every draft ends with an empty `## Diary` heading. `voice/1` deliberately
  excludes Diary ("step 5").
- `Server.Generator.run/1`: the capped model door (`{:error, :off | :capped | _}`). Reuse; never
  the render path.
- `Server.Workline.landed_since/1`: `[%{id, thread_id, title, created_at}]` of merged worklines.
- Events: `stage_advanced` rows carry `detail.bounced` (a send-back, with "sent back by X: why").
- Oban cron in `server/config/config.exs`; jobs under `server/lib/server/jobs/`.
- `test/server/soul_callers_test.exs` greps `Soul.(read|voice|tone)` callers against an allowlist.

## Decisions

1. **Diary format**: lines under `## Diary`, one per entry: `- 2026-10-14: <in-voice text>`. The date
   prefix is also the watermark (newest date = "written through"), so the job needs no new table.
2. **History source** (real rows only): per seat, since the watermark —
   *shipped* (landed worklines the seat posted on), *banked* (facts it authored; skip if the fact
   row has no author — see Task 3 note), *bounced* (`stage_advanced` with `bounced`, "sent back by
   <seat>"). QA verdicts and reviews arrive via the same bounce text; no new source (YAGNI).
3. **Voice**: model writes 1–3 lines per seat via `Server.Generator.run/1`. When off/capped/garbled,
   a deterministic fallback line per item is appended instead, so the check never needs a model
   and history is not lost. Nothing appended when a seat had no history.
4. **Weekly**: cron `0 6 * * 1`; a seat whose newest diary entry is under 6 days old is skipped
   (idempotent on retry/restart).
5. **Next week's voice reads it**: `Soul.voice/1` gains `diary: <last 2 entries, 130 chars>`.
   Not in `tone/1` (tone is Quirks/origin only; diary is content).
6. A soul file the operator hand-edited is only ever appended to under `## Diary`; other sections
   are byte-preserved. No file, no append (never creates a soul).

## Tasks (each its own commit; run `mise run check` at the end)

### T1 — `Soul.diary/1` + `Soul.append_diary/2`
Files: `server/lib/server/soul.ex`, `server/test/server/soul_test.exs`.
Test first (red): with a soul at `Soul.dir()`:
- `append_diary("daneri", ["- 2026-10-14: shipped the stanza."])` keeps every other section
  byte-identical and `Soul.diary("daneri")` returns that one entry.
- second append adds below the first; no `## Diary` heading in file → heading is added.
- unknown seat/no file → `{:error, :no_soul}`; bad name → `{:error, :bad_name}`.
Code (in soul.ex):
```elixir
@doc "The seat's diary entries, oldest first; `[]` with no soul or no entries."
@spec diary(String.t()) :: [String.t()]
def diary(name) do
  case read(name) do
    %{"Diary" => d} -> d |> String.split("\n", trim: true) |> Enum.filter(&String.starts_with?(&1, "- "))
    _ -> []
  end
end

@doc "Append entry lines under `## Diary`; other sections are untouched. Never creates a soul."
@spec append_diary(String.t(), [String.t()]) :: :ok | {:error, :no_soul | :bad_name}
def append_diary(name, lines) do
  with :ok <- check_name(name),
       path = Path.join(dir(), name <> ".md"),
       {:ok, raw} <- File.read(path) |> or_no_soul() do
    raw = if raw =~ ~r/^## Diary\s*$/m, do: raw, else: String.trim_trailing(raw) <> "\n\n## Diary\n"
    File.write!(path, String.trim_trailing(raw) <> "\n" <> Enum.join(lines, "\n") <> "\n")
  end
end

defp or_no_soul({:ok, _} = ok), do: ok
defp or_no_soul(_), do: {:error, :no_soul}
```
(Diary is the last section by design, so appending at EOF is under `## Diary`; the test for a
soul with a section after Diary should insert before the next `##` — handle with a split if the
test shows it.) Done: `mise run server:test -- test/server/soul_test.exs` green.

### T2 — `voice/1` carries the latest diary
Files: `soul.ex`, `soul_test.exs`. Test: soul with 3 diary entries → `voice/1` contains the last
two, not the first, and stays ≤ `@voice_cap`; a soul with an empty diary is unchanged (existing
tests stay green). Code: add `{"lately", last_two(name)}` to the `for` in `voice/1`, joined,
sliced to 130 each. Done: soul_test green.

### T3 — `Server.Diary.history/2` (the facts)
Files: `server/lib/server/diary.ex` (new), `server/test/server/diary_test.exs` (new).
First check: `grep -n "author" server/lib/server/fact.ex server/lib/server/message.ex` — messages
have `author`; if facts have no author, derive "banked" from `bank_fact` thread messages or drop
that source and say so in the PR (do not invent a column).
Test first: `Server.TestDB.clean!()`, open a workline thread, seat `daneri` (builder) posts a
message on it, emit a `work_landed` event with correlation `"workline:x:landing"` (as
`Server.Workline.merged/2` does), then
`Diary.history(ws, ~U[2000-01-01 00:00:00Z])` returns
`%{"daneri" => [%{kind: :shipped, title: "…", at: dt}]}`; a `stage_advanced` event with
`detail: %{"bounced" => "sent back by lonnrot: ..."}` yields `%{kind: :bounced, by: "lonnrot"}` for
the thread's builder. Seats = `Server.Workspaces.bench_all(ws)` names; a seat is credited on a
thread if it authored a message there; the `builder` archetype is credited for ship/bounce.
Done: `mise run server:test -- test/server/diary_test.exs`.

### T4 — `Diary.write/2`: model lines with fallback
Files: `diary.ex`, `diary_test.exs`. Test: with the generator off
(`Server.OperatorConfig.banter?()` false in test) `write("daneri", items)` appends one dated
fallback line per item (e.g. `- 2026-10-14: shipped "<title>".`) and returns `:ok`; with
`config :server, generator_cmd:` stubbed to echo lines (see how `soul_test.exs` stubs the
generator for `draft/2`) the model lines are appended, trimmed to `- ` lines, ≤ 3, ≤ 200 chars.
Prompt: seat's `Server.Soul.voice/1` + `Server.Persona.voice/2` + the items, "1–3 first-person
diary lines, dry, no markdown, nothing about decisions". Done: diary_test green.

### T5 — `Server.Jobs.Diary` + cron
Files: `server/lib/server/jobs/diary.ex` (new), `server/config/config.exs` (add
`{"0 6 * * 1", Server.Jobs.Diary}`), `server/test/server/jobs/diary_test.exs` (new).
Test first (the ticket's check): seat with soul file, a landed workline it posted on →
`Server.Jobs.Diary.perform(%Oban.Job{})` → `Soul.diary("daneri")` has one line mentioning the
workline title; run again → still one line (watermark/6-day guard); a seat with no history gets no
line; a seat with no soul file is skipped. Code: `use Oban.Worker, queue: :default,
max_attempts: 1, unique: [period: 3600]`; for each workspace → `Diary.history(ws, since)` where
`since` = newest diary date or 7 days ago → `Diary.write/2`. Done: jobs/diary_test green.

### T6 — keep the structural guard honest
Files: `server/test/server/soul_callers_test.exs`. Extend the regex to
`Soul\.(read|voice|tone|diary|append_diary)` and `@allowed` with `server/diary.ex` only (the job
calls `Server.Diary`, not `Soul`). Done: that test green — and it fails if `jobs/` or a workline
module ever calls `Soul.diary`.

## Verify
`cd server && mise run check` (or the repo's gate: `mise run check`) exit 0; record_check with the
real exit code. Out of scope: soul drafts, the room sim, side projects, any decision reading a
diary. Open (say so in the PR): QA verdicts are covered only as bounces; no separate QA source.
