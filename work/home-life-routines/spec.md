# Spec — Life step 4: home workspace, routines, quests, XP

Source: `docs/plans/2026-10-06-home-space-and-dollhouse-design.md` §3, §8 (step 4), §9, §10.
Scope is exactly what andrew named in thread #133 msg 2391: a `home` workspace kind, `routine`
and `quest` rows, XP/level/streak as derived views over done-stamps, `Server.Life`, routes, MCP
tools, the snapshot's `life` block. Step 5 (the life room — pulse/stamp in-tile, fridge notes,
wall calendar, header XP bar, clock-in/out walk) is explicitly **not** this step.

## 1 · Out of scope here (named so nobody infers them in)

- **No nag scheduling.** §3.1's `Server.Schedule` kind-`agent` nag, linked to a routine by title
  convention, is not created or wired by this step. A routine row exists and can be completed
  through the room/card/coworker/nag doors (§3.5) once those doors exist; this step only builds
  the three doors that don't need a room: the card's write path, a coworker's MCP call, and the
  raw API. The nag door itself is step 5+ (it needs `Server.Attention` wiring to turn an answered
  nag into a stamp, which is a UI/room concern).
- **No tiles, no room, no header XP bar, no fridge, no calendar-on-the-wall.** `tile` is stored on
  a routine (a string, validated against nothing yet — the tile catalogue doesn't exist until the
  Floor track's step 1/3) but nothing reads it to draw anything.
- **No routine packs** (§6's `POST /api/life/packs/:name`) — a later step; not in andrew's scope
  line for step 4.

## 2 · Schema

Three new tables, all owned by a workspace; the workspace-kind question is open (§8.5 below).
Migrations are raw SQL, Postgres, in the style of `20261005000000_schedule.exs` (`BIGSERIAL`
PK, explicit `CHECK` constraints for closed-set columns, `TIMESTAMPTZ`, FK `ON DELETE CASCADE`,
app-stamped `created_at TIMESTAMPTZ NOT NULL`, explicit `CREATE INDEX`, a `down/0` dropping in
reverse order) — not the Ecto DSL, matching every recent migration in this tree:

```
routines
  id              bigserial primary key
  workspace_id    bigint not null references workspaces(id) on delete cascade
  title           text not null
  every           text not null            -- cron expression, or "@daily" / "@weekly"
  window_minutes  integer not null default 60
  xp              integer not null default 10
  tile            text                     -- nullable; a tile kind name, uninterpreted here
  enabled         boolean not null default true
  created_at      timestamptz not null
  updated_at      timestamptz not null

routine_runs
  id              bigserial primary key
  routine_id      bigint not null references routines(id) on delete cascade
  due_at          timestamptz not null      -- the due instance this run satisfies
  done_at         timestamptz not null      -- set at insert; a run only exists once done
  late            boolean not null          -- computed at insert, never recomputed
  created_at      timestamptz not null      -- no updated_at: a run is immutable
  -- unique index on (routine_id, due_at): see §8.4, a one-line follow-up, not this step

quests
  id              bigserial primary key
  workspace_id    bigint not null references workspaces(id) on delete cascade
  title           text not null
  due_at          timestamptz               -- nullable: due is optional (§3.1)
  xp              integer not null default 10
  done_at         timestamptz               -- nullable until done
  created_at      timestamptz not null
  updated_at      timestamptz not null
```

Schema modules (`Server.Routine`, `Server.RoutineRun`, `Server.Quest`) follow `Server.Schedule`'s
shape: a `create_changeset/1`, closed-set validation where relevant, `Repo.insert`. New tables
need adding to `Server.TestDB`'s `@ordered` truncation list (children before parents:
`routine_runs` before `routines`), and the new contexts (`Server.Life`, and `Server.Routines`/
`Server.Quests` if split out) need adding to `server/lib/server.ex`'s `exports:` list — the
`:boundary`-enforced public surface — or nothing outside `Server` can call them.

### 2.1 Decided: `home` is a fourth `type` value

`workspace.type` is an existing closed set (`code | life | blank`, DB-CHECK'd,
`server/lib/server/workspace.ex`) that picks the roster template at creation — `life` currently
means "an assistant" (`workspaces.ex:36`), nothing to do with routines/quests. **Decided
(andrew, thread #133): `"home"` becomes a fourth `type` value** — extend the DB `CHECK` and
`@templates` with `"home" => %{type: "home", roster: [...]}`; no second column. `Server.Life`'s
routines/quests scope to any workspace of `type: "home"`.

## 3 · `Server.Life` — derived, nothing cached

No `xp`, `level`, or `streak` column anywhere. Every read recomputes from `routine_runs` and
`quests`. All functions take a `workspace_id` (routines/quests scope to one workspace) except
where noted.

- **`xp(workspace_id)`** — `Σ routine.xp over routine_runs where not late` + `Σ routine.xp / 2
  (integer div) over routine_runs where late` + `Σ quest.xp over quests where done_at is set`.
- **`level(xp)`** — `floor(sqrt(xp / 100))`, per §3.2. Pure function of an integer, no DB.
- **`next_level_at(xp)`** — the xp threshold for `level(xp) + 1`: `100 * (level(xp) + 1) ** 2`.
  The `/api/life` response also surfaces this minus current `xp` is left to the caller (room/card
  math) — `next_level_at` itself is the absolute threshold, not a remaining count, so it stays
  stable as a target even as the UI redraws.
- **`late?(due_at, done_at, window_minutes)`** — `done_at > due_at + window_minutes` (strictly
  after the window's end). Done exactly at the boundary, or before `due_at`, is on time. This is
  computed once at `routine_done` and frozen onto the run; it is never recomputed from a stale
  `done_at`.
- **`current_due(routine, now)`** — the most recent occurrence of `routine.every` that is `<= now`
  (parse `every` exactly as `Server.Schedule` already does for cron/`@daily`/`@weekly` — same
  parser, no second implementation).
- **`due(workspace_id, now \\ DateTime.utc_now())`** — every enabled routine whose `current_due`
  has no matching `routine_run` (a run whose `due_at` equals that instance). Each entry carries
  `due_at` and `window_remaining = due_at + window_minutes - now` (negative once the window has
  passed — still shown as overdue, not dropped; the room/card decide how to render a negative).
- **`streak(routine, now \\ DateTime.utc_now())`** — walk `current_due`, then its predecessor
  occurrence, then that one's predecessor, … stopping at the first occurrence with **no**
  matching `routine_run` at all (done late still counts — streak tracks "did it", xp tracks "on
  time"). The count is of matched occurrences before the break. If `current_due` itself is unmet,
  streak is `0` regardless of history before it — the plan's "counted back from now" means the
  unbroken run touching *now*, not the longest run ever.
- **`routine_done(routine_id, at \\ DateTime.utc_now())`** — resolves `current_due` for the
  routine, inserts a `routine_runs` row (`due_at` = that instance, `done_at` = `at`, `late` =
  `late?/3`), and returns `{:ok, run, level_up}` where `level_up = level(xp_after) >
  level(xp_before)`, `xp_before`/`xp_after` read from the same workspace around the insert.
  Completing a `current_due` that already has a run is a no-op error (`{:error, :already_done}`)
  — one run per due instance, never two.
- **`quest_done(quest_id, at \\ DateTime.utc_now())`** — sets `done_at`; same `{:ok, quest,
  level_up}` shape.
- **`status(workspace_id)`** — the `GET /api/life` body: `%{xp, level, next_level_at, streaks,
  due, quests, today}`.
  - `streaks` — `%{routine_id => streak}` for every enabled routine.
  - `quests` — open quests (`done_at` nil), soonest `due_at` first, then no-due last.
  - `today` — routines whose `current_due` falls on today's calendar date, "today" resolved the
    same way `Server.Schedules` resolves local "now" for a `when` (its existing local-time
    source, not a naive UTC-day comparison — see §8.5), each tagged `done: true/false`; this is
    the step 5 room's "what's on today" list, built here so step 5 adds no new query.

## 4 · Routes — `/api/life`, operator-API

Mirrors §3.4 exactly, as `Server.Office` context functions first, thin route handlers second (the
office's law):

```
GET    /api/life                      Server.Life.status/1               -> life status body
POST   /api/life/routines             Server.Life.create_routine/2        -> {title, every, window_minutes?, xp?, tile?}
PATCH  /api/life/routines/:id         Server.Life.update_routine/2
POST   /api/life/routines/:id/done    Server.Life.routine_done/1          -> {run, level_up}
POST   /api/life/quests               Server.Life.create_quest/2          -> {title, due_at?, xp?}
POST   /api/life/quests/:id/done      Server.Life.quest_done/1
```

This repo's operator API is a hand-rolled dispatcher (`Server.MCP.OperatorAPI.call/2`,
function-clauses on `[resource | rest]` + method), not Phoenix router macros — new clauses for
`"life"` alongside the existing `on_thread/4`-style helpers, same `with_workspace`/`reply/4`
helpers. The route table is a hand-kept comment block at the top of that module (its source of
truth); the six new routes get added there too.

Correction to the check line: `check:names` (`scripts/check-names.sh`) is a glue-integrity grep —
every `Server.X.Y` named in scripts/`mise.toml`/adapters/docs must have a matching `defmodule`,
every named mix/mise task must exist. It does **not** enumerate operator-API routes or MCP tool
names today, and (decided, §8.5) it stays that way. What gates the six routes: the route-dispatch
ExUnit tests this step adds (one per route, through `OperatorAPI.call/2`), plus `Server.Life`/
`Server.Routines` landing in `server/lib/server.ex`'s `exports:` list so `check:names`'
module-exists check has something real to point at.

## 5 · MCP tools

Six new tool modules under `server/lib/server/mcp/tools/`, each `use Server.MCP.Tool`, registered
individually with `component(Server.MCP.Tool.X, name: "...")` in `endpoint.ex` — the same shape as
every existing tool (e.g. `RegisterWorkspace`). **Correction to the plan's framing**: there is no
adapter that derives MCP tools from operator-API routes — routes and tools are two independent,
thin callers of the same `Server.Life`/`Server.Routines`/`Server.Quests` context functions (see
`RegisterWorkspace` next to `POST /api/workspaces` for the existing precedent). "No adapter
changes" is still true, but means the TS `adapters/` packages, not a route→tool generator — there
isn't one to change.

- `life_status`
- `routine_create`
- `routine_update`
- `routine_done`
- `quest_create`
- `quest_done`

"I brushed my teeth" said to a home-workspace coworker is that coworker calling `routine_done`
with the matching routine's id — resolving *which* routine from free text is the coworker's job
(prompt/tool-use), not this step's.

## 6 · Office snapshot

`Server.Office.status/0` (`office.ex:17-56`) returns one map with per-workspace keys already
built the same way — `triage: Map.new(ws_ids, &{&1, Room.triage(&1).count})` is the precedent. A
new top-level `life` key follows it: `Map.new(home_ws_ids, &{&1, Server.Life.status(&1) |>
Map.take([:level, :xp, :due])})` — one entry per `type: "home"` workspace, the summary only (full
`streaks`/`quests`/`today` stay behind the `/api/life` fetch the step-5 card makes, so the
snapshot never gets heavy). Absent for any workspace not of that type, same as `triage` is keyed
only by workspaces that have one.

## 7 · Test matrix (drives `menard run test --in server`)

- **xp from runs** — mixed on-time and late runs plus a done quest sum to the exact `xp(workspace_id)`
  value by the formula in §3 (on-time full credit, late half credit, integer division).
- **level from runs** — `level/1` boundaries: xp just under and just at `100 * n**2` for a couple
  of `n`, confirming the floor/sqrt curve.
- **streak with a gap** — a routine with runs on 4 consecutive due instances, a missed 5th, then
  2 more done instances after the gap: `streak/2` returns `2` (counted back from now, stopped at
  the gap), not `6`.
- **late within the window** — `done_at` at exactly `due_at + window_minutes` is `late: false`.
- **late outside the window** — `done_at` one second past `due_at + window_minutes` is `late: true`.
- **level_up on the crossing stamp** — a workspace sitting one xp below a level boundary:
  `routine_done` for a routine whose xp crosses it returns `level_up: true`; the stamp before it
  (still under the boundary) and the one after (already past it) both return `level_up: false`.
- **route-dispatch tests** — one ExUnit test per `/api/life` route, through
  `OperatorAPI.call/2`, the gate for the six routes (§8.5: no `check:names` change); plus
  `check:names` itself passing once `Server.Life`/`Server.Routines` are in `server.ex`'s
  `exports:` list.

## 8 · Assumptions made (flagging, not asking — nothing here needed andrew's call)

- `every`'s parser is reused whole from `Server.Schedule`; no second cron implementation.
- Streak counts "done" regardless of lateness; only xp discounts late. (Plan text: "the run of
  consecutive dues with a done_at" — read literally.)
- `routine_runs` has no `updated_at`: a run is written once and never edited.
- One run per due instance is enforced at the `Server.Life` level (`{:error, :already_done}`),
  not yet a DB unique index — the plan's "first time the link bites, add the key" posture extends
  here too; a unique index on `(routine_id, due_at)` is a one-line follow-up if a double-stamp
  ever actually happens.
- `today` in the snapshot/status body is today's due occurrences tagged done/not — needed by
  step 5's header and not worth a second query there, so it's built now.

### 8.5 · Decided (andrew, thread #133, msg after 2427)

- **`type` gains a fourth value, `"home"`** — no second column (§2.1). Settles the collision
  with the existing `"life"` type value.
- **No `check:names` addition.** The route-dispatch tests in the ExUnit suite this step adds are
  the gate for the six `/api/life` routes; §4's "flagged as a question" is resolved — don't touch
  `check-names.sh`.
- **The README privacy note lands in this PR** (§9's deferred item is promoted: not deferred,
  done here).
- **`today` uses `Server.Schedules`' local-time source, not UTC.** Wherever `Server.Schedules`
  resolves "now" for a cron/`@daily`/`@weekly` `when` (its own local-time boundary, not
  `DateTime.utc_now()` naively compared), `Server.Life.status/1`'s `today` field uses the same
  source for "what day is it" — so a routine due at 23:30 local doesn't fall on the wrong side of
  midnight relative to when the nag would actually fire. §3's `today` bullet is corrected by this.

## 9 · Deferred, named so they aren't silently assumed later

- Nag scheduling and `Server.Attention` wiring (step 5+).
- Routine packs (§6, later step).
- A real `(routine_id, due_at)` DB constraint, if the no-op guard above ever proves insufficient.

**Not deferred — in this PR (§8.5):** a README note on life-side privacy (plain rows, readable
by any coworker with `home`-type workspace MCP tools), per §10's "before anyone else runs a
`home` workspace."
