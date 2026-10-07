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

Three new tables, one new column, all owned by a workspace of kind `home`:

```
workspaces
  + kind  :string, default "office", not null   -- "office" | "home"

routines
  id              :bigserial pk
  workspace_id    references(:workspaces), not null
  title           :string, not null
  every           :string, not null       -- cron expression, or "@daily" / "@weekly"
  window_minutes  :integer, not null, default 60
  xp              :integer, not null, default 10
  tile            :string                 -- nullable; a tile kind name, uninterpreted here
  enabled         :boolean, not null, default true
  timestamps()

routine_runs
  id              :bigserial pk
  routine_id      references(:routines), not null
  due_at          :utc_datetime, not null   -- the due instance this run satisfies
  done_at         :utc_datetime, not null   -- set at insert; a run only exists once done
  late            :boolean, not null        -- computed at insert, never recomputed
  inserted_at     :utc_datetime, not null   -- no updated_at: a run is immutable

quests
  id              :bigserial pk
  workspace_id    references(:workspaces), not null
  title           :string, not null
  due_at          :utc_datetime             -- nullable: due is optional (§3.1)
  xp              :integer, not null, default 10
  done_at         :utc_datetime             -- nullable until done
  timestamps()
```

`kind` on workspaces: existing `Server.Workspaces.create/1` grows the one field; default keeps
every current workspace `"office"` with no migration of existing rows' data, only the column add
with its default.

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
  - `today` — routines whose `current_due` falls on today's calendar date (local to the server's
    configured timezone — same source `Server.Calendar` already reads), each tagged `done: true/
    false`; this is the step 5 room's "what's on today" list, built here so step 5 adds no new
    query.

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

Every route resolves its workspace the same way the rest of the operator API already scopes a
workspace (existing plug/param convention — not changed here). `check:names` must list all six
so a later rename fails the gate instead of stranding a route silently.

## 5 · MCP tools

The same six, one-to-one with the routes, for a coworker employed by (or consulted in) a `home`
workspace — the adapter's existing route→tool mapping needs no change, only the six new routes
registered:

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

`Server.Office.status` grows a `life` summary block, computed by calling `Server.Life.status/1`
and projecting down to `%{level, xp, due: [...]}` (the detail fields — `streaks`, full `quests`,
`today` — stay behind the `/api/life` fetch the step-5 card makes; the snapshot only carries what
the step-5 header needs so it never gets heavy). Only present when the viewer's current/linked
workspace is `kind: "home"`; absent otherwise, same as any workspace-scoped block today.

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
- **`check:names`** — the six `/api/life` routes resolve in whatever manifest `check:names`
  walks, alongside the existing route set.

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

## 9 · Deferred, named so they aren't silently assumed later

- Nag scheduling and `Server.Attention` wiring (step 5+).
- Routine packs (§6, later step).
- A real `(routine_id, due_at)` DB constraint, if the no-op guard above ever proves insufficient.
- README note on life-side privacy (plain rows, readable by any coworker with `home` workspace
  MCP tools) — §10 says this lands "before anyone else runs a `home` workspace," i.e. by this
  step's PR; tracked here so it isn't dropped.
