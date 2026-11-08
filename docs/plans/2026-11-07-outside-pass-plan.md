# An outside pass — what to improve, and who builds it (2026-11-07)

**Status:** proposed by Uqbar from a read-only audit of the repo, the live database, the saved
memory of the last two months of sessions, and three subagent reads (server, office, adapters +
scripts). Nothing here is built. Andrew hands the items to Opus and Sonnet sessions; each lands
through review and the merge queue like any other change.

## The diagnosis in one line

The machine works; what it loses now is **turns and attention to noise** — a notice posted six
thousand times, a hook that refuses two hundred commands a fortnight, a snapshot rebuilt from
twenty-five queries ten times a minute, a seat that cannot read the ticket it was staffed on — and
**the fun stopped at step 7** of three designs whose step tables still say "open".

## How to read an item

Each item is one ticket (or one small PR). It carries **Why** (the evidence, measured where it says
a number), **Change** (the minimum that meets the need), **Check** (the command or test that goes red
before and green after), **Who** (`Opus` for design judgement or the landing path; `Sonnet` for a
well-specified change; `Haiku` for a one-liner) and **Size** (S under a day, M a few days, L a
workline with a spec). A **limit** mark means the risk grade will list a limit (a migration, a
dependency, the check or CI, AGENTS.md or the spec), so its gate passes up to Andrew, never to Uqbar.

Numbers were read 2026-11-07 from the `tlon` db unless stated. Fourteen days = 2026-10-24 to
2026-11-07.

---

## A · Stop the noise (cheap, do first)

**A1 · The "read dirs left out" notice is posted on every spawn.** `Sonnet · S`
- Why: 7,633 notices in 14 days, 6,356 of them on the standing thread of workspace 1; one line
  per seat launch, from `server/lib/server/mcp/spawn.ex:226`. It is 80% of all notices and the
  largest writer to the `message` table (267 MB for 29k rows).
- Change: say it once per (seat, launch fingerprint) — the fingerprint already exists
  (`Server.Profiles.fingerprint/1`) — or log it to the seat's `citizen-<author>.log` instead of
  posting. Keep the content.
- Check: a test spawning the same seat twice posts the line once; after a day live, the count of
  that notice ≈ the number of seats.
- Done: already shipped before this pass was built — e16575e made `read_dirs_export/1` (spawn.ex) post the
  notice only when that exact body is not on the thread yet (once per thread; a changed dropped list still
  posts), and `spawn_test.exs` "read dirs the shared budget leaves out are posted once on the thread"
  spawns twice and asserts one post. Live db on 2026-11-08: no message starts with the notice, 17 mention
  it (none after 2026-11-01). No code change.

**A2 · Menard's filter hook refuses instead of rewriting.** `Sonnet · S · in menard, not tlon`
- Why: ~200 of the 271 `tool_denied` events in 14 days are one rule:
  `menard … 2>&1 | head -c 3000` refused with "menard's reply is read whole". Every seat hits it.
- Change (in `~/projects/menard/lib/menard/scripts.ex`, `filtered?/1`): strip the filter and run the
  bare command with a one-line note, as the operator's own session hook does for `mix test | tail`;
  cap big replies on menard's side so the fear of a huge reply goes away. Handed to a menard session
  separately; listed here so the tlon count is the check.
- Check: `select count(*) from event where kind='tool_denied' and detail like '%read whole%' and
  created_at > now()-interval '1 day'` → near zero.

**A3 · The brief does not say what a seat cannot run.** `Haiku · S`
- Why: "python3 does not run here" is the next refusal (~10 in 14 days); a seat learns it by losing
  a turn.
- Change: one line in the role prompt (`adapters/claude-code/launch.sh`'s system prompt, or the
  `TLON_ROLE_PROMPT_FILE`): no python, node, perl or ruby in a seat; text edits go through menard.
- Check: `lib/launch.test.ts` asserts the line is in the rendered prompt.
- Done: the line ends `launch.sh`'s citizen prompt; the test reads it from the dry-run exec line.

**A4 · Sessions pile up behind a seat and are reaped loudly.** `Opus · M`
- Why: "retired N earlier session(s) of tzinacan still holding this seat (pid …)" appears 60+ times
  in 14 days, mostly for the reviewer seats (tzinacan, lonnrot, runeberg); four and five pids at a
  time. `Server.Orphans` is doing its job; the question is why reviewer sessions survive their
  verdict so often (a review's session is ended by its verdict, `Server.Staffing.end_review/1`).
- Change: find the mechanism (likely the window closing before the process exits, or `review_branch`
  sessions with no leaf window), fix it at the source, and make the notice say the count once per
  seat per day rather than per spawn.
- Check: the notice count in 7 days under 10; `select count(*) from session where ended_at is null`
  matches the roster.
- Read 2026-11-08: the notice has not fired since 2026-11-03 20:40, zero in the five days since, so
  the count check holds without a throttle. Every notice was on a workline thread, and its 2 to 8
  pids were one seat's process tree (every child inherits `TLON_THREAD`/`TLON_AUTHOR`), not that
  many sessions. It stopped the evening seats began running without the operator's worktrunk plugin
  (79609d7), whose hooks write `.git/config` on each prompt and stop; that its hook processes were
  the survivors is likely, not shown, because the notice named only pids. Done: the notice counts
  processes and names each one's command (`pid 101 claude, 105 wt`), so a recurrence says what
  outlived its window. Open: two `session` rows open with no pane (tertius on t1, uqbar on t269).

**A5 · 464 junk `gate` rows in `schedule_run`.** `Sonnet · S`
- Why: `schedule_run` holds 464 failed + 29 ok rows with `check_name='gate'`, no schedule and no
  thread, in bursts seconds apart with exit 143 — the release-smoke test suite posting `ran-on` to
  the live service. #786 stopped the posting on 2026-11-04; the rows remain, and
  `Server.Release.Candidate.newest/1` reads by `check_name` and `sha`, so a stray row can answer for
  a real check.
- Change: a one-shot `tlon-cli` verb or `server:db-sweep` case that deletes `schedule_run` rows with
  no `schedule_id` and no `thread_id`; make `Candidate` read only schedule-bound rows.
- Check: the count is 0; `mise run release:status` answers the same before and after on a known sha.
- Done by data, 2026-11-08: the live table holds 0 `gate` rows with a null `schedule_id` (read over
  `bin/server rpc`), so nothing to sweep. The "read only schedule-bound rows" half is dropped: hand
  runs record through `Candidate.record/3` (`record-ran.sh`, and a landing's gate since E2) with no
  schedule, so that read would blind `release:status` to them. Telling a hand run from a test's stray
  post needs a column (who posted it), a migration: Andrew's call, not built.

**A6 · An `erl_crash.dump` sits at the repo root since 2026-11-04.** `Sonnet · S`
- Why: two dumps, both "Runtime terminating during boot … io.put_chars standard_error … the device
  does not exist": a short-lived VM hit an error, tried to print it, and its stderr was gone. The
  root one (14:31) is OTP 29 on one scheduler, `tlon-cli.sh`'s `bin/server rpc` client node
  (`ERL_FLAGS +S 1:1`); the one in `server/` (10:28) is OTP 27 on 20 schedulers, menard's own
  toolchain (`.tool-versions`), so a menard VM run from `server/`. Neither is the service (the
  journal is silent at both times), yet `server:doctor` blamed the last restart (#855).
- Change: done 2026-11-07 — both dumps moved to `~/.local/state/tlon/crash-dumps/`, and
  `tlon-cli.sh` sets `ERL_CRASH_DUMP` there, so a client node's crash never lands at the root again.
  Done 2026-11-08: `Doctor.crash_dump/3` also reads the state dir and dates the newest dump against
  the service start; a client node's dump is said to be no service's, before the start or after.
  `tlon-cli.sh` points a closed stderr at `/dev/null` (bash hands the freed fd 2 to the script
  itself), so its VM never dies printing a boot error; test `tlon-cli.test.sh`.
  Left: which caller closes stderr is unidentified (`server-restart.sh` and `release.sh` send it to
  `/dev/null`, which works, and no dump has landed since) — read the next dump in the state dir;
  menard's half (its VM dumping into the caller's cwd) goes to the menard session with A2.
- Reproduced 2026-11-07, OTP 27 and 29: `printf 'raise "boom"\n' > boom.exs; elixir boom.exs 2>&-`
  (or `… 2>&1 >/dev/null | true`, stderr a pipe whose reader has gone) leaves `erl_crash.dump` in
  the cwd; stderr to `/dev/null` does not. `Kernel.CLI.exec_fun` (cli.ex:155) prints the script's
  exception with `:io.put_chars(:standard_error, …)`, the write fails (`ebadf`/`epipe`) and raises,
  the handler at cli.ex:170 prints *that* to stderr and fails again, and the exception escapes
  `Kernel.CLI.run` into `init:start_it`: "Runtime terminating during boot". Filed upstream as
  elixir-lang/elixir#16079. The dumps sat at the root and in `server/` because `mise -C <dir> exec` changes
  directory to the project first and the VM dumps in its cwd.
- Check: no dump at the root in a week; #855 closed.

**A7 · Stall notices fire twice per thread.** `Haiku · S`
- Why: "⚠ stalled — tN is mid-turn and its pane has not changed for 5m" posts twice for the same
  thread (t530, t501, t359 each twice in 14 days).
- Change: dedupe on (thread, since the pane last changed) in `Server.Maintain.Sweep` or the alert.
- Check: a test with two passes in the stale window posts once.
- Done: the second post was a stall resolved by hand while the pane stayed frozen (inferred from the code; the live rows were not inspected); the row now carries `since` and `Stall` posts once per freeze. Test: `attention_stall_test.exs`.

**A8 · A stopped `mise run check` frees the queue while its suites still run.** `Sonnet · S`
- Why: seen 2026-11-07 while landing this plan: the shell running `check` was stopped, the
  checks-queue lock was released at once, but `mix precommit`'s BEAM and the office suite's tmux
  sessions kept running in the checkout; the next `check` in the same checkout raced them on
  `server/tmp` (`test_helper.exs:28`, `File.rm_rf!` "file already exists") and went red.
- Change: `scripts/checks-queue.sh` runs its command in its own process group and, on any exit
  signal, kills the group and waits for it before releasing the lock, and records the group in
  `$XDG_RUNTIME_DIR/tlon-checks.group`; the next check is refused (exit 2, naming the group) while
  that group still has members.
- Check: `checks-queue.test.sh` gains a case: a stopped holder leaves no child alive and the lock is
  taken by the next waiter only after; a check beside a surviving group exits 2 naming it.
- Done: `checks-queue.sh` stops the group on TERM/INT/HUP and waits for it to be gone (KILL after `CHECKS_KILL_GRACE`, 30 s) before releasing the lock (polled in the script, so no timer holds the lock); a queue killed outright leaves its group, and the next check exits 2 naming it (`CHECKS_IGNORE_LEFTOVERS=1` runs anyway). Not a cwd scan: a watcher, LSP BEAM or menard run in the checkout is not a leftover. Tests: `checks-queue.test.sh`.

---

## B · Performance — the server

**B1 · The office snapshot is rebuilt on every GET.** `Opus · M`
- Why: `Server.Office.status/0` (`GET /api/office`) runs ~25 sub-queries, a `Room.board` per
  workspace, `Room.health` (which runs `df`), `Server.Tmux.list_windows` per workspace and
  `Rollout.revs`, on every call. The TUI polls it every 10 s and follows with `needs`, `settings` and
  card loads; `Server.Jobs.Drain` rebuilds every Need each minute (`NeedsPage.run/0`), including a
  `git for-each-ref` shell-out (`Needs.work_tips/1`). Nothing is cached or conditional.
- Change: (a) build once per 1–2 s and share: an ETS/`persistent_term` entry invalidated by a PubSub
  "dirty" signal (the `held_windows/1` fallback is the pattern); (b) an ETag or `rev` on
  `/api/office` and `/api/office/needs` so an unchanged snapshot is a 304; (c) `df` cached 60 s;
  (d) `work_tips` cached on the refs' mtime or filled by `KeepUp`; (e) `NeedsPage` runs on a bus
  event or when the Needs fingerprint changed, not every minute.
- Check: a telemetry test asserting `Office.status/0` ≤ N queries and `Needs.all/0` ≤ M (pin N and
  M to today's counts first, then lower them); the TUI's refresh latency in `tui/flight.ts` logs.
- Measured 2026-11-08 on the live node: `Office.status/0` 425–500 ms and 231 queries (271 ms of
  them in the db; 114 were `Tickets.epic_of/1` per ticket), `Needs.list/0` 510 ms and 182 queries
  (110 were five per open thread for `tool_denied`, none of which had a refusal), `NeedsPage.run/0`
  430 ms. So the cost is B2's per-row reads, not the absence of a cache; and a cache invalidated on
  every write (the snapshot reads nearly every table) would rarely hit. Done with B2: the counts no
  longer grow with tickets or worklines (two tests pin it), by bulk reads for a ticket's epic and
  thread, the latest message per thread (`Staffing.parked_notes/1`), the threads refused twice,
  when each workline last moved, the benches and each repo root. (a) and (b) are dropped until a
  measurement after release says the snapshot still costs too much; (c)–(e) stay open.
- Done 2026-11-08, (c) and (d): `Room.health/0` reads tmux, disk and memory through the minute-old
  `vitals/0` (it forked `df` on every snapshot beside a cache the needs list already used), and
  `Needs`' `work_tips/1` holds each root's `for-each-ref` for 60 s (a stall is hours old). Left:
  (e) — `NeedsPage.run/0` still derives every need each minute to find the new ones; a fingerprint
  would need the same pass, so it waits for a cheaper `Needs.list/0` or a bus event per kind.

**B2 · N+1 queries on the hot passes.** `Sonnet · M`
- Why (read, not profiled): `Office.tickets/2` calls `Tickets.epic_of/1` and `thread_of/1` per open
  ticket; `Office.Needs.all/0` calls `Workspaces.bench/1` and `Channel.thread_lead/1` per open
  workline thread; `Server.Staffing.pass/1` fetches the last message per thread one by one
  (`parked_note?/1` too); `Maintain.Sweep` runs `Repo.exists?(message …)` per doing ticket;
  `Office.status` calls `Projects.in_workspace/1`, `Workspaces.policies/1` and `bench_all/1` once per
  workspace.
- Change: bulk-load `ticket_link`/`ticket_thread` for the workspace's ids into maps; preload
  bench-by-workspace and leads once at the top of `Needs.all/0`; one `DISTINCT ON (thread_id)` query
  for the latest message per thread; `where workspace_id in ^ids` for the per-workspace reads.
- Check: the query-count tests from B1 drop; `mix test` unchanged.
- Done 2026-11-08 for `Office.tickets/2`, `Needs` (`no_seat`, `tool_denied`, `stalled`, `seats`)
  and `Office.threads`' parked seat, with B1. Open: `Staffing.pass/1`, `Maintain.Sweep`'s per-ticket
  `exists?`, `Office.status`' per-workspace reads, and the 39 `Thread` gets in `Needs.list/0`.

**B3 · Indexes the hot filters lack.** `Sonnet · S · limit (migration)`
- Why: `pg_indexes` today — `thread` has only `agent_id` and a partial `slug`; `ticket` has only its
  primary key; `event` has `thread_id`, `kind`, `correlation` separately; `message` has `thread_id`
  but not `(thread_id, id)`. Yet `thread.state='open'` + `workspace_id`, `ticket.workspace_id` +
  `status`, `event(thread_id, kind)` and "latest message on thread" run on every pass.
- Change: one migration: `thread(workspace_id, state)`, `ticket(workspace_id, status)`,
  `ticket(project_id)`, `event(thread_id, kind)`, `message(thread_id, id desc)`, `session(agent_id)
  where ended_at is null`.
- Check: `EXPLAIN (ANALYZE)` on `Office.status`'s three biggest queries before and after, pasted in
  the PR; `psql \d thread` shows them.
- Done: migration `20261108120000_hot_filter_indexes` (Andrew merges it). `EXPLAIN (ANALYZE)` on the live db, indexes made in a rolled-back transaction: open threads of a workspace Seq Scan (525 rows) -> Index Scan `(workspace_id, state)`; tickets by workspace+status Seq Scan (804 rows, 110 buffers) -> Index Only Scan, by project Seq Scan -> Index Scan; `event` by thread+kind Index Scan on `thread_id` with a Filter -> Index Cond on both; latest message of a thread pkey backward scan with a Filter -> Index Only Scan `(thread_id, id desc)` (a quiet thread: Sort -> none). `session(agent_id)` left out: its plan did not change, `session_one_live_per_thread_agent` already serves it. At 500-800 rows the gain is small today; the plans stay flat as the tables grow.

**B4 · Embeddings are JSON text decoded in Elixir on every brief.** `Opus · L`
- Why: `server/lib/server/vector_column.ex` stores vectors as text and decodes them per fact per
  brief (`Server.Recall`, `@meaning_pool 500`); the moduledoc still says SQLite. `fact` is 60 MB for
  6.6k rows; `message` also carries an `embedding` column.
- Change: measure brief latency first (`get_brief` p50/p95 over a day via telemetry). If it
  matters, pgvector with an HNSW index and cosine in SQL; if not, an ETS cache of decoded vectors
  for the pool and a corrected doc. Either way, confirm which `message` kinds are embedded — if
  notices are, stop (A1's 7,633 lines would each carry a vector).
- Check: the brief latency number before/after in the PR; `select pg_size_pretty(sum(length(
  embedding))) from message where kind='notice'` → 0.
- Measured 2026-11-08 on the live node: a brief took 2.5–8.6 s; with a query vector, knowledge
  recall 2.5–2.9 s and learnings up to 3.6 s, of which decoding 500 vectors' JSON was ~680 ms and
  the list cosine ~670 ms, each paid twice per brief. And the query embedding timed out on every
  brief after a quiet spell: ollama unloads the model after 5 min, a reload takes ~6 s, recall waits
  1 s and its giving up aborts the load. Done: `Server.Recall.Vectors` caches each fact's unit
  vector packed and scores by dot product (no migration, no dependency); requests send
  `keep_alive: 24h`; notices are no longer embedded on write. Measured live after the hot-load:
  brief median 1.0 s warm, 1.2 s cold. Open: the 3,142 notices already
  embedded (28 MB) stay until the operator nulls them; pgvector stays the larger fix, a migration
  and a dependency, Andrew's call.

**B5 · Shell-outs have no timeout; nine private `git/2` helpers.** `Opus · M`
- Why: 96 `System.cmd`/`Port` uses in `server/lib` and only `Server.ModelCli` and `Server.Smoke`
  bound the call. A hung `gh` or `git` in `workline/publish.ex`, `jobs/land.ex`, `pr_landing.ex`,
  `keep_up.ex` or `release/pm.ex` blocks the single-concurrency `landing`/`maintain` queue until
  Oban's Lifeline rescues it after 180 min (the gh-keyring hang of 2026-10-22 was exactly this).
  `git/2-3` is re-implemented in `worktree.ex`, `pr_landing.ex`, `recall/probe.ex`,
  `workline/artifacts.ex`, `scribe.ex`, `docs.ex`, `merge.ex`, `release/pm.ex`, `canvas/paint.ex`.
- Change: one `Server.Cmd.run/3` (args, cwd, timeout → `{:ok, out} | {:error, :timeout | …}`) and a
  `Server.Git.run/3` on it; migrate the landing-path callers first, then the rest; a timeout is a
  recorded failure on the thread, never a silent hang.
- Check: a test that a stubbed command sleeping past its timeout returns `{:error, :timeout}` within
  the bound; `grep -c 'System.cmd' server/lib` falls to the two wrappers.
- Done 2026-11-08: `Server.Cmd.run/3` is `System.cmd/3` through coreutils `timeout` (default 120 s,
  `timeout: :infinity` for a command with its own wall), answering `{out, 124}` with the output
  saying it timed out — the shape every caller already reads as red, so the 17 injected
  `run \\ &System.cmd/3` defaults and the landing path moved with no call-site change;
  `Server.Git.cmd/3` and `run/3` replace the nine `git/2` helpers and the direct `git -C` calls
  (35 → 8). `cmd_test.exs` holds a `sleep 30` at `timeout: 1` to exit 124 in under 8 s. Left: 47
  bare `System.cmd`s — the gate scripts (`bash` with their own walls), `kill`/`pgrep`/`cp`/`df`,
  the bench runner and the compile-time one in `profiles.ex`; `#781`/`#864` (a vanished seat as an
  ending) stay with Staffing.

**B6 · One-shot Oban jobs retry never; `Process.sleep` in GenServers.** `Sonnet · S`
- Why: `max_attempts: 1` on Staff, Maintain, Triage, Grade and TurnPass; fine for a per-minute job,
  not for Grade, EndReview or Land, where a transient db or git fault drops the step (`grade.ex:294`
  hand-rolls a 30 s sleep retry). `Process.sleep` sits in `switchboard.ex:465`, `attention.ex:531`
  and `orphans.ex:80`, on the wake hot path.
- Also: a restart during a run is a failure with no cause. `machine:update` on 2026-11-07 22:30
  stopped the service 23 s into a Maintain run (they take 18–52 s), systemd's 10 s stop timeout
  SIGKILLed it, and the job was discarded as "no error recorded" (`Server.Jobs.Alarm`).
- Change: `max_attempts: 3` with backoff on the one-shot jobs — `2` on Maintain, every sweep in it
  idempotent; the alarm says "killed by the restart at HH:MM" when the job's node died rather than
  raised; `Process.send_after` or a Task for the three sleeps.
- Check: a test that a Grade job raising once completes on the second attempt; the switchboard's
  wake latency test (exists) still passes.
- Done: Maintain `2` (Land, EndReview, Verify already had 3); Grade stays at `1`: a rerun asks the paid
  grader again and posts another "risk grade" message, so it is not idempotent. Staff, Triage and
  TurnPass stay at 1 (per-tick passes run again next tick; TurnPass stamps before it extracts, so a
  rerun does nothing). `Orphans.requeue` says "killed by the restart at HH:MM" for each discarded
  orphan. Open: the three sleeps are not in a GenServer callback (the switchboard's is already in a
  Task, attention's in the answering request, orphans' in the spawn path), so they stay; the test
  for "Grade raising once" asserts the attempts, not a live retry.

**B7 · Pass-duration telemetry.** `Sonnet · S`
- Why: five crons fire every minute (Drain, Staff, Dispatch, KeepUp every 5); `staff` has
  concurrency 1 and `unique period: 300`, so a slow pass silently skips ticks and nobody sees it.
- Change: `:telemetry` spans on each `Jobs.*.perform/1`; a `job_slow` Need (or a sheriff note) when a
  pass exceeds 30 s; the number on `server:doctor`.
- Check: `server:doctor` prints the last pass durations; a test with a slowed pass raises the Need.
- Done: no new telemetry code: Oban's own `[:oban, :job, :stop]` span is the span on every `perform/1`,
  and the rows it stamps (`attempted_at`, `completed_at`) are read by `Server.Jobs.Passes` (Drain, Staff,
  Dispatch, KeepUp; not Maintain, 18-52 s by design). `server:doctor` prints `passes:`; a newest pass
  over 30 s (finished within 15 min), or a pass executing now for over 30 s, is `health:job_slow` among
  the box's Needs, no new Need kind, so the office TUI is untouched. The Needs read takes it from a 30 s
  `:persistent_term` cache (`Passes.slow_cached/0`), not a query per read.

---

## C · Performance — the office TUI

**C1 · Every frame is PNG-encoded before the diff.** `Sonnet · S`
- Why: `tui/paint.ts kittyImage` upscales the whole floor up to 5×, inks it, runs `png()`, base64s
  it, and only then compares with `lastImageData`; an unchanged frame pays everything. It also
  encodes the full floor when `viewport` is a crop (the home below the office).
- Change: hash `fr.rgba` + `fr.ink` first and skip encoding when unchanged; crop to the viewport
  before upscaling and re-place on pan rather than re-send.
- Check: a bench test (`test/paint-bench.test.ts`) counting `png()` calls over 50 identical frames
  → 1; the golden frames unchanged.
- Done: `kittyImage` keys the encode on a hash of `rgba`, ink and cover plus scale (and the viewport only when a balloon is placed against it); 50 identical frames call `png()` once, 12 ms to 2 ms per frame on a 320×200 floor at 3× (`test/paint-bench.test.ts`). Left: cropping to the viewport before upscaling — the placement already crops the one transmitted image, so a pan never re-sends; a crop would re-encode on every pan.

**C2 · `png.ts` does a byte loop CRC and no filter.** `Sonnet · S`
- Why: `for (const x of b)` CRC over the whole IDAT per frame, unfiltered scanlines at deflate level
  1, a `Buffer.concat` copy.
- Change: `Bun.hash.crc32` (or zlib's), rows written into one preallocated buffer, a PNG sub-filter
  (sprite art compresses far better). Keep `f=100` PNG: `o=z` crashes ghostty.
- Check: the same bench; bytes per frame and ms per encode before/after in the PR.
- Done: `Bun.hash.crc32`, one output buffer, a sub filter that skips repeated pixels; a 960×600 floor encodes in 8.9 ms (was 27.6) and 45.9 KB (was 94.4 KB), still `f=100` PNG; the encoded PNG is decoded back by pngjs in `test/paint-bench.test.ts`.

**C3 · The sim rebuilds layout and finds threads per person every tick.** `Sonnet · S`
- Why: `kit/sim.ts step` calls `plan.layout(a)` every 100 ms though the snapshot changes every
  ~10 s, and `a.threads.find` per actor makes it O(people × threads) at 10 Hz; `[...actors.values()]`
  is copied in several per-tick helpers.
- Change: memoise layout and a thread `Map` on snapshot identity; a cached actor array updated on
  add/remove.
- Check: `test/sim.test.ts` has a tick-cost assertion (ticks per ms over 10k ticks) that goes up.
- Done: `layoutFor` memoises per snapshot (a WeakMap), `view()` in main is held until `all` or the workspace changes, `Sim` holds a thread `Map` and the held snapshot per snapshot and a cached actor array; 2000 ticks on one snapshot went from 4.7 to 7.7 ticks/ms (`test/sim.test.ts` asserts the layout is shared across ticks and logs the rate).

**C4 · Contrast backing is recomputed per label per frame.** `Sonnet · S`
- Why: `tui/paint.ts inkInto behind()` scans every pixel under every label box at k× each frame to
  decide backing, for hundreds of labels.
- Change: cache the decision by (text, colour, position, underlying-region hash) until the region's
  art changes.
- Check: `wcag.test.ts` unchanged; the paint bench's ms per frame drops.
- Left: not built. `test/paint-bench.test.ts` times `inkInto` over 300 labels at 3×: about 4 ms a frame, all of it the backing scans plus the glyph writes. A label box is a fixed ~1.5k px whatever `k` is (text size follows `textScale`, not `k`), so hashing the region under each costs as much as scanning it; a region-hash cache measured no faster. Reopen if a room ever carries labels in the thousands.

**C5 · Timers ignore focus.** `Sonnet · S`
- Why: `tui/main.ts` polls `data.focus()` every 1 s, stat-checks seven followed files every 1 s,
  runs `pollPlayer` as `Bun.spawnSync(["playerctl" …])` every 2 s (blocking, even with no
  playerctl), shakes the phone every 1 s while N > 0, and refreshes every 10 s — all unfocused too.
  (The room clock already stops unfocused since 2026-11-06.)
- Change: gate each `every(...)` on `focused` with a 30–60 s unfocused cadence; `fs.watch` or one
  merged stat for the files; async `Bun.spawn` with a 30 s backoff after a non-zero exit.
- Check: a test that drives focus off and counts timer firings over 5 s.
- Done: `tui/pace.ts paced` runs a timer body every tick focused and once per 30 s unfocused (the focus request: 5 s, since another surface asks the TUI to show a thread); on it the refresh, the followed-file stats, the focus poll, the activity poll and `pollPlayer`, which is now async `Bun.spawn` and waits 30 s after a failed run; the phone shake, note fade and pet/store preview draw only when focused. Test: `test/pace.test.ts` counts firings over a fake clock. Left: `fs.watch` for the seven followed files (the stats are one per second focused, one per 30 s not).

**C6 · `draw()` rebuilds header, card rows and pane at room-frame rate.** `Sonnet · M`
- Why: each 10 Hz frame re-renders the whole room *and* `detail()` and `drawPane`.
- Change: split the pane draw from the room draw; redo the pane only when state or the snapshot
  changed (the `fresh`/`imageDirty` flags already half-exist).
- Check: the paint bench; the drive walks (`office/test/drive/run.sh`) read the same screens.
- Done: the room clock's frames repaint the room and its tip alone (`paint(true)`, re-setting the pane's input caret); the header and `drawPane` run on the tick's other draws and once a second. The `wide` drive walk reads the same screens before and after (one typed-in-finder timing difference); its two `click:#201`/`#202` steps fail the same on the unchanged base in this environment — open, not caused here. Left: the frame time is not measured (no harness drives `draw()` headless); the pane is at most a second behind a state change that calls no `draw()`.

**C7 · Conditional snapshot fetch** — the client half of B1(b): send `If-None-Match`, keep the held
snapshot on 304. `Sonnet · S`, after B1.
- Left: not built. B1(b) was dropped (the snapshot's cost was B2's per-row reads) and the server sends no `ETag` and honours no `If-None-Match` on `/api/office`, so a client half would be dead code. Reopen with B1(b): `data.status` keeps the `ETag` of the last 200, sends it as `If-None-Match` and on 304 returns `lastGood` unchanged.

---

## D · Agent ergonomics (the biggest lever on throughput)

**D1 · A seat cannot read the ticket it was staffed on.** `Opus · M`
- Why: there is no `get_ticket` tool; `list_tickets` renders through `MCP.Brief.ticket/1`, which
  drops `body`, and takes only `include_done` (no status, assignee, label or limit). A workline
  started from a ticket gets the title in its brief and nothing else.
- Change: `get_ticket(id)` with the body, links and sightings; `list_tickets(status, assignee,
  label, limit)`; a `TICKET` section in the brief (`Server.Board.brief/2`) for the thread's linked
  ticket, body capped with a "[cut N chars; get_ticket(id)]" tail.
- Check: `server_test` for both tools; the brief eval scenario for a ticket-started workline shows
  the section.
- Done 2026-11-08: `get_ticket(id)` (this workspace's only; the body whole, links as
  `list_tickets` gives them), `list_tickets(status, assignee, label, limit)`, and a `## Ticket` section
  heading the brief for the ticket the thread was started from, its body cut at 4,000 chars with a
  `[cut N chars; get_ticket(id)]` tail (`Tickets.started_from/1`, `MCP.Brief.brief_ticket/1`). Open: no
  eval scenario added; tested in `server_test`, `board_test` and `brief.test.ts`.

**D2 · Reading a cited thread, and who is on what.** `Sonnet · M`
- Why: `get_messages`/`get_brief` take no thread id, so a notice citing `#473` can be followed only
  one `get_message(id)` at a time; "who is on what" exists only as the CLI `roster` and the band's
  `office_glance`.
- Change: a read-only `get_thread(id, limit)` for a lead and the threads its notices cite
  (`Server.MCP.Tool.may_post?/2`'s rules decide who may read); a `roster` tool (agent, thread,
  status, doing) that is `Server.Coworker.status/1` over the live sessions.
- Check: tool tests; the coordinate skill (D7) points at them.
- Done: `get_thread(id, limit)` (the caller's own thread, or one it `may_post?` on; bodies cut as the brief's) and `roster` (the caller's workspace, `Office.roster/1` rows: agent, thread, title, status, doing) in `reads.ex`; no profile change, since every profile gets a tool unless it excludes it; the coordinate skill points at them. Tested in `server_test`.

**D3 · Refusals that say nothing.** `Sonnet · S`
- Why: `catch_up_branch.ex:22`, `coordination.ex` (`staff_child`, `switch_thread`, `spawn_crew`,
  `kill_crew`, `close_thread`, `consult_peer`), `workline.ex:38,97,104,209,272`, `branch_review.ex`,
  `oracle.ex:43`, `workspace.ex:450` answer `inspect(reason)`; `librarian.ex:113` returns
  `inspect(result)` as a *success*; the seat-cut refusal "X's seat does not have <tool>" names no
  alternative.
- Change: one `Server.MCP.Tool.explain/1` mapping the known reason atoms and tuples to a sentence
  plus the next action, `inspect` as the fallback; the seat-cut refusal names who has the tool or
  what to post instead.
- Check: a test per mapped reason; `grep -c 'inspect(reason)' server/lib/server/mcp/tools` → 0.
- Done: `Server.MCP.Tool.explain/1` maps the reasons the contexts return (advance, landing, ticket start, consult, spawn, model CLI) and the tools call it; the seat-cut refusal says to post to the lead; librarian's `decide_proposal` no longer returns an inspected struct.

**D4 · `consult_peer` exists but the skill and the ticket say it doesn't.** `Sonnet · S`
- Why: `Server.MCP.Tool.ConsultPeer` is registered (`endpoint.ex:50`), cut from coworker profiles
  (`profiles.ex:328`; the sheriff keeps it, `:358`); the coordinate skill (`adapters/skills/coordinate-*/SKILL.md:31`) says "you
  have no `consult_peer`"; ticket #573 asks for a peer channel; memory records "@tertius please
  relay" as the workaround.
- Change: decide once — give workline leads `consult_peer` (a lead asking a builder on a thread it
  cites is the case #573 names) or keep the cut and close #573 with the relay rule written into the
  skill. Recommend giving leads the tool.
- Check: `profiles_test` pins which archetypes have it; the skill names it.
- Done: the truth-sync half only: the coordinate skill says the tool exists, is cut from coworker profiles, the sheriff keeps it, and that `@tertius` relays; `profiles_test` pins the sheriff as the one archetype that has it. Left: the decision (give leads `consult_peer`, or keep the cut and close #573) is Andrew's and stays open; no profile changed.

**D5 · Brief size and two names for one tool.** `Sonnet · S`
- Why: OPENING is the operator's first message uncut and each of the 5 recent messages is rendered
  whole (`renderChatter` in `claude-code/lib/brief.ts`), so one long paste dominates a brief;
  `get_brief` and `get_dossier` are one module under two names; `life.ex`'s six tools take a bare
  `workspace_id` while every other tool reads identity from the connection.
- Change: cap opening and message bodies at a few KB with "[cut N chars; get_message(id)]"; keep one
  name and mark the other an alias in its description; bind the life tools to the caller's
  workspace.
- Check: `brief.test.ts` with a 20 KB opening renders under the cap; tool tests.
- Done: `MCP.Brief.brief_message/1` cuts the opening and each recent message at 4,000 chars with `[cut N chars; get_message(id)]` (the tool's answer), and `renderChatter` cuts the same in `brief.ts`; `get_brief` is `GetBriefAlias`, "Alias of get_dossier" in its description; the six life tools take no `workspace_id`, they act on the connection's workspace (`Tool.life/2`), and a routine or quest of another workspace is `not_found`. Left: `brief.ts` never rendered OPENING, so the 20 KB check is on a chatter body; the operator's session no longer reaches the home workspace's life rows from a thread in another workspace.

**D6 · The band never says the server is down.** `Sonnet · S`
- Why: `lib/citizen.ts bandParts` renders the last dossier with no age or error marker;
  `dossierAt`/`dossierError` are tracked and unused. A seat on a dead server looks healthy; the
  glance's red count freezes silently.
- Change: append "· offline Ns" (dimmed) when the last good dossier or glance is older than the
  poll interval ×3.
- Check: `citizen.test.ts` with a stale `dossierAt`.
- Done: `offlineNote` (citizen.ts) reads the newer of `dossierAt` and a new `glanceAt`; the seat's band appends it dimmed, and a failed glance poll now redraws so the age shows.

**D7 · The skills are stale in five places.** `Haiku · S`
- Why: `bank-what-you-learn` says "a dedicated question type is coming" (`raise_question` exists)
  and "hunch" where the brief prints `opinion`; `verify-with-evidence` sends everything through
  `cap` while a seat uses `run_verb`/`run_task`; the coordinate skill tells an agent to use
  `/consult` (an operator command), mentions an undefined "claude", and carries the node name in
  its own directory name and its prose, where the glossary allows it for the node only (rename it
  `coordinate-via-tlon`). `check-glossary.sh` does not scan `adapters/skills/` or tool descriptions.
- Change: fix the five; extend `check-glossary.sh` to `adapters/skills/*/SKILL.md` and
  `server/lib/server/mcp/tools/*.ex` descriptions. `limit` (the check) for the second half.
- Check: `mise run check:names` green with the wider scan.
- Done: the five skill fixes and the `coordinate-via-tlon` rename (README, brief.ts, brief.test.ts updated); the brief prints `[hunch]` for `opinion`, so the skill now says "hunch" throughout. Not done: the `check-glossary.sh` extension (Andrew's limit gate); `funes` remains in `keep-todos-current`, `verify-with-evidence` and `bank-what-you-learn` prose.

**D8 · `tlon-cli.sh` is a second implementation of fifteen tools.** `Opus · M`
- Why: 661 lines, no `.test.sh`, inline Elixir strings for `ticket-start`, `ticket-set`,
  `forget-fact`, `land-pr`, `branch-review`, `advance`, `send-back`, `dossier`, `read`, `post`,
  `close-thread`, `hand-off`, `ticket-file`…; it is also the identity hand-off (`token`) for every
  launcher. "andrew" is hardcoded at lines 506, 514 and 629, and in `claude-code/lib/brief.ts:133`.
- Change: where the CLI holds a token, call the MCP tool (as `dossier` does under `TLON_MCP_URL`);
  the rest become `mix tlon.*` tasks or `scripts/tlon-cli/<verb>.sh`; a `token`/usage test with the
  existing `TLON_CLI_CURL` stub; `Server.OperatorConfig.operator/0` for the name everywhere.
- Check: `scripts/tlon-cli.test.sh` in `check:names`; `grep -n andrew scripts adapters` → the
  README's example only.
- Done 2026-11-08, the name: the rendered dossier carries `operator` (`Brief.scope/1`,
  `OperatorConfig.operator/0`), `renderBrief` reads it when no `TLON_OPERATOR` is given, and the
  CLI's four inline-Elixir sites call `OperatorConfig.operator()`; `grep -n andrew scripts adapters`
  is the test files only. Left: the fifteen verbs' MCP/mix-task split and the `token`/usage test
  (the `.test.sh` itself arrives with A6 in #816 — build on it once merged); `office/tui/main.ts`
  still defaults the name from the env.

---

## E · The pipeline (friction the backlog and the memory show)

**E1 · Jobs that end without telling anyone.** `Opus · L (spec first)`
- Why: a cluster of open tickets is one defect — a job ends and no thread hears it: #793 (a
  `review_branch` verdict posts nowhere; PR #766 sat approved 13 h), #841 (a failed restart after a
  cut is silent), #846 (`PRLanding.post(nil, _)` drops the outcome), #864 (a workline in another
  repo is staffed but its lead never launches), #781 (a spawned reviewer's window vanishes with no
  verdict), #750 (release-smoke's build-lock wait is silent and unbounded), #812 (a scheduled restart
  is lost between the quiet check and the restart).
- Change: an invariant — **every `Server.Jobs.*` ending, success or failure, posts one outcome on a
  thread** (the work's thread, else the standing thread, else the sheriff's beat) — enforced by a
  test that drives each job's failure path and asserts a post; then the seven tickets are the
  instances. Pairs with B5's timeouts (a timeout is an ending).
- Check: the invariant test; the seven tickets closed by it or by their own PRs.
- Spec 2026-11-08: `docs/plans/2026-11-08-e1-job-endings-spec.md`, awaiting Andrew. It finds only
  #846 and #793 are a job ending unsaid; the other five are scripts, units and vanished seats,
  each its own fix (#781 and #864 go with B5).
  Done: #793 (`BranchReview.record/1` posts the verdict on the review's thread and the branch's workline thread).
  #841 (`PM.cut` posts a refused restart on the root thread; `release.sh` exits 1 on the restart's 409).
  #750 (the smoke's build-lock wait is bounded by `TLON_SMOKE_BUILD_WAIT`, 1200s, and says so).
  #812 (`server-restart.sh` in a redeploy unit tells the server, `tlon-cli restart-refused`, which posts
  on the root thread and schedules the restart again, so it stays pending).

**E2 · A landing's gate already is `check:main` on the new tip — record it.** `Opus · M`
- Why: `release:status` today: main is two commits past the release and "no check:main on 92b914e;
  its last run was on 2da459f". The merge queue gated exactly that tree (rebased onto origin/main,
  `workline-verify.sh` branch mode) minutes before it became main's tip, then the nightly runs the
  same suite again at 03:00 and the smoke at 03:30. Ticket #820 names the starvation.
- Change: when a landing's gate passes on the tree that then becomes main's tip, record it as
  `ran-on: check:main <sha>` (the `record-ran` path), so `Server.Release.Candidate` is satisfied by
  the gate that already ran; queue the smoke on that sha after the merge (it is 3 min). The nightly
  stays as the backstop.
- Check: after a landing, `mise run release:status` shows the gate ✓ on main's tip without a
  nightly; the smoke ✓ within 10 min.
- Done 2026-11-08, the gate half: `Publish.merge_at/5`, which both the merge queue and a workline's
  publish merge through, calls `Candidate.landed/3` on an immediate merge. When the repo is tlon's and
  origin/main's tip holds exactly the tree the gate passed, it records `gate` ok on that tip. GitHub's
  rebase rewrites the commits, so the tree is compared, not the sha. Open: the smoke is not queued
  after the merge; an auto-merge armed instead of merging records nothing; unverified live until a
  landing through `mise run land`.

**E3 · Intake's cap and the held pile.** `Opus · M`
- Why: 97 backlog + 20 doing against `max_worklines: 3`; held tickets take slots (#851, #512);
  60 of the open tickets carry `held`, some since 2026-10-08 (#32–#36, #237, #357); a review ticket
  waits behind the cap (memory: `route-review-tickets`).
- Change: (a) held tickets never count toward the cap (#851); (b) review tickets bypass intake's
  rank (they are the merge queue's input); (c) a weekly "held review" from the PM seat: one post on
  the standing thread listing held tickets over 30 days with keep / close / unhold as answers, so
  the pile is a decision, not a sweep.
- Check: `intake_test` for (a) and (b); the PM's schedule posts the list; the backlog count a month
  on.
- Done 2026-11-08, (a) and (b): a held or review `todo` ticket holds no slot, and a backlog review
  ticket is routed each pass ahead of the rank and at any cap (`Intake.next_review/1`). Open: (c),
  the PM's weekly held review.

**E4 · The operator's own words are not banked.** `Opus · M`
- Why: `fact` holds 6,602 derived facts and **24 stated** (one tombstoned); `server/docs/issues.md`
  #2 named this the primary gap ("99.9% of MY writing is into this box") and the mod has a
  correction detector on `prompt.submit`, yet standing calls reach the store only when Uqbar is told
  "bank it" (the eight most recent stated facts are all that shape).
- Change: measure first — count `prompt.submit` hits where the detector fired vs banked over a
  week (a counter in the citizen log). Then: the operator's posts on the office (`talk.ts`, the
  reader, `tlon-cli post`) and the `claude:operator` session's turns go through the same detector,
  and a detected standing call is banked `stated` with the message id as provenance, with a one-line
  "banked: …" echo so a wrong bank is seen and `forget_fact`ed.
- Check: `provenance='stated'` grows on days Andrew talks (the issue's own check).
- Done 2026-11-08, the measure: the mod's `prompt.submit` writes `correction detected: <text>` and
  its capture writes `banked N facts, M questions` to `citizen-<author>.log`, so a week's ratio is
  `grep -c` over the log. Left: the banking itself (office posts and the operator session through
  the detector, banked `stated` with the message id), after the count says how often it fires.

**E5 · The Uqbar sends-back change (PR #746 / ticket #819).** `land it`
- Why: five gates in one day waited on Andrew for a fix the reviewer had already named; the call is
  made (fact 6233) and the PR exists.
- Change: review and land #746; then the memory rule `uqbar-sends-back` applies.
- Check: `mise run land -- 746`; a gate with a named fix goes back to build from Uqbar's session.
- Done: #746 merged 2026-11-01 (67fc126) and is in the live release.

**E6 · The high-priority open tickets, routed as a batch.** The pipeline's own bugs, each already a
ticket; this plan only orders them: #851 (cap), #793 (verdict silent; E1), #614 (tertius with no
pane: intake waits 30 min), #812 (lost restart; E1), #813 (`out of usage credits` not seen as
quota), #727 (a builder seat without `push_branch`/`catch_up_branch`), #864 (other-repo lead never
launches; E1), #861, #820 (E2), #541 (bwrap source path for t1), #622 (fact_relevance bound),
#760 (menard `run test` times out at 620 s with no verdict), #806 (smoke test flake), #749 (intake
notice on the sheriff's beat). `Sonnet` for each but #614 and #760 (`Opus`).
- #614, found 2026-11-08: the manager does answer an intake in seconds once seated; what waited out
  the 30 minutes (#857 on 2026-11-05) was the arbiter reading the manager's leaf window on another
  thread (its inbox-sweep duty, t190, tagged `@funes_agent tertius`) as its lobby seat, so the lobby
  wake was `:already_running` until the duty closed. Fixed: on the standing thread only a non-leaf
  window counts.
- Routed 2026-11-08: #851, #813, #727, #541, #622, #806, #749 and #760 sent to tertius in that
  order (`tlon-cli ticket-route`); #861 was already doing; #793, #812 and #750 are built on
  `e1-instances`, #614 fixed above, #820 is E2, #864 waits on Staffing.

**E7 · Fewer check runs, the same safety.** `Opus · M (spec first) · limit (the check)`
- Why: one change runs the full suite up to five times: the builder's own `run_task("server:check")`
  before advancing, the verify gate on the rebased branch, the landing gate rebased onto main, the
  nightly `check:main` on a tip that is often that same tree, and a review send-back repeats the
  middle two. `check_passed` events: 2,676 in 14 days. Each run is minutes of the one machine, the
  checks queue serialises them, and the script test suites (`check:names`'s nine) run every time
  whatever changed. Andrew (2026-11-07): "we are running a looooot of checks; keep the safety, run
  less of them".
- Change, four mechanisms, each keeping the rule that nothing merges that nobody checked:
  1. **One green per tree, everywhere.** `check.sh` already skips a clean tree it has passed
     (`~/.cache/tlon-verify/green`). Widen it: the key is the tree hash *minus* `work/` and `docs/`
     (a `pr.md` or a plan commit does not make a new tree to test) — done 2026-11-07, keeping the
     two docs files a check reads (`docs/glossary.md`, `docs/manual/tasks.md`); `run_task("server:check")` runs
     `mise run check` so a seat's green is recorded and verify becomes a cache hit; the record is a
     `check_passed` row in the db, not a per-checkout file, so every checkout and the nightly see it.
  2. **Scope verify by what changed, keep landing full.** Verify runs the suites of the modules the
     diff touches (`server/` → `server:check`, `office/` → `office:check`, `adapters/` → its two,
     `scripts/`/`tasks/` → `check:scripts`, docs only → `check:names`); two or more modules, or a
     touch on `mise.toml`, `scripts/check*.sh` or `AGENTS.md`, runs the full set. The landing gate
     stays full and is the one GitHub's `tlon/check` is posted from.
  3. **The landing's gate is the nightly** (E2): recorded as `ran-on: check:main <sha>`, so the
     03:00 run skips when main's tip already has a green; the smoke queues after the merge.
  4. **The canary bench runs on a changed steering fingerprint**, not nightly (`mix
     server.bench_contrast --fingerprint` already computes it); the script suites run when
     `scripts/` changed (G6's `check:scripts`).
- Spec 2026-11-08: `docs/plans/2026-11-08-e7-fewer-checks-spec.md`, awaiting Andrew. Measured ~5
  passed suites per landing over the week to 2026-11-08; the landing gate stays full throughout.
- Check: the count of `check_passed` events per landed workline, read for a week before and after
  (today's shape is ~4–5 per landing); every landed PR still carries a `tlon/check` from a full run
  at exactly its head; a change to `server/` alone never skips the server suite (a test over the
  scoping function with fixture diffs).

---

## F · Fun (the office)

The three designs (toy, souls, home) stopped with their step tables saying "open"; everything below
is a step from one of them or a cheap extension of a mechanism that exists. **Already built, don't
re-propose:** per-seat reactions to all six events, six visitor kinds with Halloween and carol
dates, the Konami disco, Valentine's note, October pumpkins, December tree, the TV's New Year
countdown and release channel, the facing fix for Argos's chase (2026-11-07).

**F1 · Side projects on the corkboard** (souls step 4, ticket #323). `Sonnet · M`
- Why: `kit/souls.ts` parses "The side project" and nothing renders it; Daneri's growing poem and
  the others were the design's best joke.
- Change: a daily `CorkNote` per seat from its soul's side-project line, generated through
  `Server.Office.Corkboard` (the server already writes corkboard chatter), state kept so the poem's
  stanza count grows.
- Check: after two days the corkboard shows two stanzas; `corkboard_test`.

**F2 · The diary speaks.** `Sonnet · S`
- Why: souls step 5 writes a weekly diary (`Server.Soul`) and the client parses the section
  (`kit/souls.ts`) but never shows or quotes it.
- Change: the last diary line on the person card; `Sim.onTogether` quotes a diary line one time in
  ten instead of the banter table.
- Check: `souls.test.ts`; seen in the sandbox with a seeded soul.

**F3 · A compiled-in pool so the room has lines with no server.** `Sonnet · S`
- Why: generated puns and visitor lines reach the room through `Sim.pooled()` but `weirdness`
  defaults to `curated`, so the pools are empty; puns fire 30% after a visit; `GENERIC_REACT.gary`
  is one line.
- Change: a small handwritten pool (20 puns, 10 visitors, 3–4 generic lines per event kind) in
  `kit/seat-voices.ts`; the generated pool extends it rather than replacing nothing.
- Check: the sandbox never repeats a generic line twice in a row; `events.test.ts`.

**F4 · The play card pages, and every event is summonable.** `Sonnet · S`
- Why: the sandbox's play card is capped at digits 1–9 (`play.*` in `tui/keys.ts`), so no toy can be
  added; `CHAINS` in `kit/events.ts` is reachable only under the `rimworld` preset; there is no row
  for the zoo van, the power cut, or a Gary + zoo chain.
- Change: page the card (`[`/`]` or a second digit row), one row per `EVENT_KINDS`, a "chain
  reaction" row; show the card once on first sandbox launch.
- Check: `keys.test.ts` (one meaning per key) green; each row plays in a drive walk.

**F5 · Three new events from existing props.** `Sonnet · M`
- Why: six event kinds, two with empty `CHAINS`.
- Change: a paper-plane storm (`kit/plane.ts`, Argos catching), a pizza party (the door's pizza,
  everyone to the kitchen, grease on the whiteboard), and a power nap (lights dim, everyone's head
  down, Nina on the warmest keyboard). Each tidies itself and touches no thread or turn.
- Check: `events.test.ts` per kind; each in the play card.

**F6 · Pastimes get a pose and a line.** `Sonnet · M`
- Why: `draw.ts` has no branch for aquarium, chat, pet, vending, foosball, pool or bathroom (the
  figure just stands there); `SEAT_VOICE` has `banter` and `sore` only.
- Change: a few-frame pose per pastime (a poke at the tank, a coin into the vending machine, a lean
  on the sink, a cue lined up); `Voice.at: Partial<Record<Pastime, string[]>>` so a line matches the
  place.
- Check: `draw.test.ts` renders each pose; the golden frames re-hashed on purpose.

**F7 · The home's missing tiles and presets.** `Sonnet · M`
- Why: `CATALOGUE` in `kit/home.ts` has six kinds; the design lists gym, hall, pond, balcony,
  workshop, music-corner, trophy-shelf, tank. `PRESETS` in `kit/pets.ts` has `nina-and-argos` only
  (design: `cat-only`, `menagerie`, `pond-life`, `none`); no floor presets (`studio`, `house`,
  `loft`, `cabin`, `campus`), so a new user starts from an empty page.
- Change: gym (the streak sets the dumbbell size) and trophy-shelf (the streak photos) first, then
  pond; the four pet presets; a `FLOORS` catalogue in `kit/floor.ts` with `studio` and `house`.
- Check: `homeart.test.ts` per tile; the build mode drive walk places each.

**F8 · Argos fetches the newspaper** (home whimsy; a brief exists in `work/`). `Sonnet · S`
- Change: a morning errand on the existing `dogDo`/fetch machinery: out the front door at the first
  snapshot after 07:00, back with the paper to the operator's desk; the headline is the day's first
  landing or "nothing yet".
- Check: `pets.test.ts` under the seed; seen once live.

**F9 · The office's own trophies.** `Sonnet · S`
- Why: no achievements anywhere; the kids initiative asked for exactly this kind of thing.
- Change: an `office-trophies` file in the state dir — first fire drill, 100 treats, 1,000 balloons
  read, 10 planes caught, a week of green nights — shown on a card and as a shelf object; a
  "secrets: 0/3" row in the sandbox for the eggs.
- Check: `trophies.test.ts`; the card.

**F10 · A day has a shape.** `Sonnet · S`
- Why: `moment(kind, hour, …)` weights spots by hour but nothing marks lunch or home time; seasons
  cover October, December and 14 February only.
- Change: a 12:00 lunch rush to the kitchen, a 17:30 leaving wave that pairs with lights out; a
  `seasonOf(date)` table (spring blossom at the window, summer fan, Pi Day on the clock face,
  New Year's Eve beyond the TV).
- Check: `daylight.test.ts` and `sim.test.ts` at pinned clocks.

**F11 · A TV channel that is the office.** `Sonnet · S`
- Why: twelve generative channels, none about the work.
- Change: a ticker channel (`kit/tv.ts`) reading the snapshot's release sha, the merge queue, the
  phone count and the newest landing's subject.
- Check: `tv.test.ts`; sandbox.

**F12 · Uqbar's errands grow with the room.** `Haiku · S`
- Change: three errands in `kit/volume.ts`: visits the hall, inspects a new hire, brings Argos a
  hat. Check: `volume.test.ts` under the seed.

**F13 · Six quiet keys nobody can find.** `Haiku · S`
- Why: `tab`, `R`, `p` (pat Nina), `U` (Uqbar), `.`, `,` are handled and hinted nowhere.
- Change: list them in the help card's "everywhere" section. Check: `keys.test.ts`.
- Done: `everywhere()` in `tui/keys.ts` lists every global, quiet included; the help card uses it, the foot still skips them.

---

## G · Code health, docs and the dev loop

**G1 · The two god files.** `Opus · L each`
- `server/lib/server/workline.ex` (2,497 lines; stage machine, gates, send_back, review and QA
  verdicts, self-review, landing, requeue, PR merge, ledger; ~12 rescues) → `Workline.Stage`,
  `Workline.Review`, `Workline.Landing`, `Workline.SendBack`, a thin facade. With menard's `module`
  verbs, in slices, each slice its own PR with the suite green.
- `office/tui/main.ts` (2,836 lines, 115 top-level functions, 74 module-level state variables) →
  `tui/cards/*.ts` for the `detail()` builders, `tui/boot.ts` for the timers, a state object passed
  in. Same slicing.
- Next in line: `operator_api.ex` (1,286; one `route/4` list → per-resource routers),
  `office/needs.ex` (1,203; one module per Need generator under a behaviour, which also makes B1's
  per-kind caching possible), `staffing.ex` (908), `profiles.ex` (1,310).
- Check: file sizes in the PR; `mise run check` green; no behaviour change (the suites are the
  check).

**G2 · The whiteboard is implemented twice.** `Sonnet · M`
- Why: `rooms/rail.ts` and `rooms/wide.ts` each build `boardColumns`/`stickyItems`/`COL_W`/`PER_COL`
  and the hit rectangles, the desk `layout()`, and the cork notes.
- Change: `kit/board.ts` (`whiteboardItems(a, ctx)`, `hitFor(person)`) and a shared `seatPlan(a)`;
  the rooms keep geometry only.
- Check: `rail-portable.test.ts` (no `node:` import) and the golden frames unchanged.
- Done: `kit/board.ts` holds `whiteboardItems` (the TICKETS stickies folded in), `hitFor`/`idOf` (a line's tip and
  target) and `seatPlan`; both rooms use them. `boardColumns` already lived in `kit/crew.ts`; the rooms' desk
  `layout`s differ in geometry only. Suite (972) and golden frames green. Left: the cork notes stay per room (ink
  and slots differ); a rail sticky's tip now carries `#id` like the wide room's.

**G3 · Determinism is claimed and not enforced.** `Sonnet · S`
- Why: 85 `Math.random` calls in `kit/` and `rooms/` (33 in `sim.ts`); `kit/rng.ts` exists; the
  docs say "deterministic under the test seed".
- Change: every call through `rng.ts`; `seatLine`/`soreLine` reuse `pick`/`pickFresh`.
- Check: an eslint/grep rule in `office:check` that fails on a bare `Math.random` under `kit/` and
  `rooms/`. `limit` (the check).
- Done: every `kit/` and `rooms/` call goes through `random()` in `kit/rng.ts` (it reads `Math.random` at call
  time, so the tests' stubs still pin it); `seatLine`/`soreLine` use `pickFresh`/`pick`. `test/determinism.test.ts`
  (run by `office:check`) fails on a `Math.random` anywhere else under `kit/` or `rooms/`. Left: `tui/main.ts` has
  one `Math.random` (a cheer's pick) and `tui/terminal.ts` one (a tmux name); the gate covers `kit/` and `rooms/` only.

**G4 · The glossary's pending renames.** `Opus · M · limit`
- Why: all four are still undone — `Server.Crew`/`Crew.Tmux` → `Server.Spawn`; `Server.Staffing` →
  `Server.Sweep` (collides with `Maintain.Sweep`: decide the name first); the standing thread's
  stored title (`bootstrap.ex:24 @standing_title`, needs a data migration); the release gate as a
  Need of kind `gate` with `scope: release` (`needs.ex:290` and `alerts.ex:149` still emit `dialog`).
- Change, in order: the title migration; `dialog` → `gate`; the two module renames with
  `menard rename`, each its own PR; the glossary rows lose `pending:`.
- Check: `mise run check:names` green with the `pending:` markers removed.

**G5 · Dead and stale things the tree says exist.** `Haiku · S`
- `adapters/{consult,footer,pi,reload}/` hold only untracked `node_modules` and empty `.claude`
  stubs — delete; `adapters/claude-code/plan/` is a second tracked mod no doc names — fold or
  delete, and say which in `adapters/AGENTS.md`; `server:import-pi`, `Server.Import.PiSessions` and
  the pi mention in `check:names` are residue of the retired harness; `vector_column.ex` says
  SQLite; `config/config.exs`'s Oban comments are interleaved wrongly; the home design's status
  table says the grid offset "is read but not yet applied" while `office/AGENTS.md` says `loadFloor`
  handles it (one of them is wrong — check, then fix the loser); `office/AGENTS.md` has paragraphs
  over 1,500 characters on one line (split per area under `office/docs/`, AGENTS.md as the index).
  `limit` (AGENTS.md).
- Done: `adapters/{consult,footer,pi,reload}/` do not exist in a clean checkout (only the live one's untracked
  leftovers; nothing to delete in git). `claude-code/plan/` is kept: `launch.sh` loads it for a Claude-plan seat
  and the claude-code README names it; `adapters/AGENTS.md` now says why it is a mod of its own.
  `server:import-pi` and `Server.Import.PiSessions` (with its test) are deleted, the pi mentions in the
  `check:names` and server task text are gone. `vector_column.ex` already says Postgres. `config.exs`'s
  comments sit above what they describe. The design's status row was the wrong one (home tiles are placed at
  their cells, with a street and doors): fixed there. `office/AGENTS.md` is an index; the three long area
  bullets moved verbatim to `office/docs/{kit,rooms,tui}.md` (the glossary gate scans them).
  Left: `ClaudeSessions` still parses pi's transcript format; the live checkout's untracked adapter dirs.

**G6 · The check's shape.** `Sonnet · M · limit (the check)`
- Why: `check:names` runs nine scripts serially with `&&` (the release-smoke and checks-queue tests
  are the slow ones); `server:check` is `mix precommit && mix server.eval --deterministic`, serial
  inside the parallel `check:suites`; `server:deps` runs `mix deps.get` every time; `check` →
  `check.sh` → `check:all` → `check:suites` is three nested mise layers; `adapters:claude-code:mod`
  needs a live `claude` and fails the whole check on a box without one.
- Change: split `check:scripts` (the `.test.sh` files as parallel `depends`) from `check:names`
  (the grep gates); `server:eval-det` as its own task in the parallel set with its own db name;
  `mix deps.get --check-locked`; `check.sh` calls `check:suites` once; the mod check skips with a
  clear line when `claude` is absent.
- Check: `mise run check` wall time before/after in the PR (read from `.logs/`); green.

**G7 · The suite is mostly serial; the TUI tests boot tmux twenty times.** `Sonnet · M`
- Why: `async: true` in 50 server test files, `async: false` in 153; `Process.sleep` clusters in
  `corkboard_test` (9), `needs_test` (8), `random_test` (4); the lib has clock knobs
  (`:attention_settle_ms`, `:grader_retry_ms`) tests could set to 0. About 20 office test files each
  boot the TUI in tmux with a 120 s first-paint budget; 43 fixed sleeps.
- Change: move the pure server tests to async under the SQL sandbox (a pass over the 153, one PR per
  dozen); sleeps → `assert_receive` or the clock knobs; one shared sandbox TUI per office test file;
  a `--no-animate` flag so first paint excludes the sim; a `waitFor(screenContains)` helper.
- Check: `mise run server:test` and `office:test` wall time before/after; no new flake in a week of
  nightlies (a flake is fixed, never retried).
- Done (step 1, sleeps): `needs_test` waits no more: its eight `Process.sleep(1100)` (8.8 s of the file's
  run) are `put_away_earlier/0` and `time_passes/1`, which age the put-away and the thread's rows by two
  seconds in SQL so the next row is newer at the clock's whole-second grain; `corkboard_test` and
  `random_test` wait for the writer tasks to finish (`settle`: the task supervisor idle, the GenServer's
  mailbox flushed) instead of 30-300 ms sleeps. The poll loops that return the moment the condition holds
  stay. Whole server suite before: 2712 tests, 14:47 wall at load ~20 (`menard run test --in server`);
  the three files' wall time reads 42 s before and about 60 s after at load 22-28, which is startup and
  load, not the tests: by `--slowest`, `needs_test`'s three slowest went 3.5 s, 2.4 s, 1.3 s to 1.2 s,
  0.8 s, 0.7 s. The knobs `:attention_settle_ms` and `:grader_retry_ms` were already set to 0 where the
  tests need them (`config/test.exs`, `attention_test`, `gateway_test`).
- Done (step 2, async): the suite has no SQL sandbox (`test_helper.exs` makes one shared database and
  `Server.TestDB.clean!/0` truncates it), so a test that reads or writes it cannot be async: that is the
  finding for the 153. Of the 153, three touch no shared state at all (a private tmp dir and subprocesses,
  or an instance under its own name) and are flipped: `calendar_test`, `commits_test`, `harness_test`.
  `bus_test` (the global PubSub firehose), `focus_test` (a global Agent), `release_test` (migrates the
  shared database) and `hot_load_test` (a global compiler option) look pure and are not. Whole server
  suite, both runs green: 14:47 before (2712 tests) -> 12:15 and 10:43 after (steps 1 and 2 together,
  at load 16-28 with other suites on the box, so the wall times are loose). Left: a dozen needs a
  per-test sandbox (or a database per async module) first; Open: the first run's `flaky` retry of
  `worktree_test.exs:620` (retire/2 drops the test database), which passed on its retry and on the second
  run; it creates and drops databases through psql and shares nothing with the three flipped files, but
  its cause is not found.
- Done (step 3, office): `office/test/wait-for.ts` is `waitFor(screen, want, what, budget)` (text, pattern or
  a test of the screen, failing with the pane); it replaces the fixed sleeps that have something on the
  screen to wait for (`reply-box`, `room-key`, `margin-tip`, `persona-reroll`, `cast-view`), and
  `column-tree` shares its one TUI between its two tests (ctrl-] to the room between them). `office:test`
  before: 972 pass, 329 s at load 21; after: 972 pass, 200 s at load 10 (the load differs, so the gain
  is not all the change's). Left: the sleeps with nothing on the screen to wait for stay (`navigation`'s
  300/250 ms after esc, `cast-view`'s 600 ms for a file that must stay unchanged, `reply-box`'s 1500 ms
  focus-poll baseline, `terminal`'s 200 ms for a placeholder that must not appear, `tree-reorder`'s 150
  ms per cursor step); the ~25 file-local `until` copies still poll on their own (moving them to
  `waitFor` is a mechanical follow-up); `rack-card`, `reply-box` and `terminal` boot per test because
  each test changes what the server answers or needs a clean first paint; the `--no-animate` flag is
  not done, `office/tui/main.ts` being PR #818's.

**G8 · 59 GB of worktrees — mostly `du` double-counting; the sweep's one real gap.** `Sonnet · S`
- Why: `du` counts every checkout's `server/deps` (1.9 GB) and `_build` in full, but
  `Server.Worktree.seed_deps/2` copies them `cp --reflink=auto`, so on btrfs they share blocks:
  `btrfs filesystem du -s .worktrees` read 29.9 GiB total and **353 MiB exclusive** (2026-11-07,
  after the closed threads' checkouts went). What had piled up was 13 checkouts of closed threads,
  kept by the sweep for a stale `.claude/settings.json` edit an older launcher wrote (current seats
  read clean) and for `landed?/4`'s file match, which reads a landed workline's branch as unmerged
  once main edits the same files again (`toy-step-4`, `uqbar-step-4`, both landed in October).
- Change: done 2026-11-07 — `Sweep.reap_worktrees/0` retires a closed *landed* thread's checkout
  whatever `git cherry` says (its change is on main; the branch stays), with a test. Left:
  `server:doctor` reports `.worktrees` as exclusive bytes (`btrfs filesystem du` where it exists,
  `du` elsewhere) so the number stops alarming; and `Channel.close_thread/1` on a *landed* thread
  whose checkout reads unmerged (the main checkout behind origin, say) answers `{:tracked, _}` —
  promoting it back to build — which `Workline.merged/2` match-crashes on: a landed thread closes
  as landed, its checkout retired, never tracked.
- Check: the strays test; `btrfs filesystem du -s .worktrees` exclusive under 1 GB.
- Done 2026-11-08: `Worktree.unmerged?/2` trusts `git cherry` alone (the file match, `landed?/4`, is
  gone; a squash-merged branch now reads unmerged, which tlon's rebase-only main never makes);
  `worktree_size/2` puts `.worktrees` as exclusive bytes on `mix server.doctor`'s `worktrees:` line.
  The `close_thread` bullet needed no code: a thread at stage `landed` already closes through the
  non-tracking clause, and a strays test now holds it (`Workline.merged/2` on a landed thread whose
  checkout reads unmerged closes it and the sweep retires the checkout). Tests: `worktree_test.exs`,
  `doctor_test.exs`, `strays_test.exs`.

**G8b · A new checkout trusts its own `mise.toml`.** `Sonnet · S`
- Why: mise loads a project config only once it is trusted, and an untrusted one fails silently
  for a caller reading JSON: `mise ls -C <checkout>` then reports the machine's global pin
  (erlang 27 on the home machine), so a host `mix` runs on the wrong OTP and `_build` recompiles
  on every switch (A6: the OTP 27 dump in `server/`). `check-main.sh`, `release-smoke.sh` and
  `workline-verify.sh` already `mise trust -q` the checkouts they make; `Server.Worktree.ensure/2`
  and `scripts/scratch.sh new` do not. The home machine now also lists `~/projects` and
  `~/.cache/tlon-scratch` in mise's `trusted_config_paths` (2026-11-07), which no other machine has.
- Change: `ensure/2` and `scratch:new` run `mise trust -q <checkout>` after the checkout exists
  (ignore a missing mise); `server:doctor` names a seat or scratch checkout whose `mise.toml` is
  untrusted.
- Check: a worktree test that `mise trust --show -C <checkout>` reads trusted after `ensure/2`;
  `scratch.test.sh` the same for `new`.
- Done: `Worktree.ensure/2` and `scratch.sh new` run `mise trust -q <checkout>` (a missing mise ignored); `mix server.doctor` prints a `mise trust:` line naming untrusted seat and scratch checkouts (`Doctor.untrusted_checkouts/2`). Tests: `worktree_test.exs`, `doctor_test.exs`, `scratch.test.sh`.

**G9 · Scripts without tests, and six copies of `expect()`.** `Sonnet · S`
- Why: `release.sh` (the pointer cut and rollback), `check.sh` (the tree-cache rules),
  `server-restart.sh` (cuts work off), `land.sh`, `tlon-cli.sh`, `workline-verify.sh` have no
  `.test.sh`; the six existing test scripts each define `expect`, `say`, `fail`, `until_log`, `pg`,
  `cleanup`.
- Change: `scripts/lib/test.sh` sourced by the `.test.sh` files; tests for `release.sh` and
  `check.sh` first.
- Check: the new tests in `check:scripts` (G6).

**G10 · `work/` holds 304 directories of finished worklines.** `Opus · S (decision)`
- Why: 620 tracked files, 3.4 MB — the artifact chain of every workline ever, at the repo root.
  Cheap today; a decision, not a fix: archive landed worklines' `work/<slug>/` under
  `work/.landed/<yyyy-mm>/` at the cut, or leave them and say so in AGENTS.md.
- Check: whichever is chosen is written down.
- Recommendation 2026-11-08, for Andrew's call: leave them. The 3.4 MB costs nothing a reader meets;
  the chain under `work/<slug>/` is what `Workline.Artifacts`, the retro and the librarian read by slug,
  so an archive move needs every reader to look in two places for the rest of the repo's life, for a
  tidier `ls`. If chosen, one line in `AGENTS.md` under the worktree rules: "`work/<slug>/` is kept after
  landing; it is the workline's record." The other way (archive at the cut) stays open as a ticket if
  the count ever matters.

---

## Sequencing

| Order | Items | Why this order |
|---|---|---|
| 1 | A1 A2 A3 A5 A6 A7, E5, F13 | hours each; the noise stops the same day, Uqbar's send-back unblocks gates |
| 2 | E6 (the high tickets), A4, D3, D6, D7, B6, B7 | the pipeline's own bugs and the cheap ergonomics; no design needed |
| 3 | B1 B2 B3, C1–C7 | the two performance passes; B3 is one migration, gated by Andrew |
| 4 | D1 D2 D4 D5, E1 (spec), E2, E7 (spec) | the throughput lever, the "no silent end" invariant, and fewer check runs |
| 5 | F1–F12 in any order, each its own ticket under the Toy / Home and whimsy epics | the fun, sized small on purpose; a Sonnet seat each |
| 6 | B4 B5, E3 E4, D8, G1–G10 | the long ones; each a workline with a spec |

## Who

- **Opus:** A4, B1, B4, B5, D1, D8, E1, E2, E3, E4, E7, G1, G4, G10, #614, #760.
- **Sonnet:** everything else that is `Sonnet`; each item above is specified to the file and the
  check on purpose, so the brief is the item itself plus the files it names.
- **Haiku:** A3, A7, D7, F12, F13, G5.
- **Andrew:** the gates that list a limit — B3, D7's check extension, E7, G3, G4, G5, G6 — and the two
  decisions: D4 (does a lead get `consult_peer`) and G10 (`work/` archive or not).

## Not in this plan, on purpose

- Nothing about which model a seat runs on: `docs/models.md` and the role bench own that.
- No rework of what the fun section lists as built; no re-reading of the five designs' prose —
  their step tables are cited above where a step is open.
- No hand cleaning of `.worktrees/` while any sandboxed command runs (the `.git/config.lock` mount),
  and never the live checkout's branch: G8 does it through `Worktree.retire`.
