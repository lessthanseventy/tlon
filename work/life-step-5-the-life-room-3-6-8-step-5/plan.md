# Life step 5 — the life room — plan

Design: `docs/plans/2026-10-06-home-space-and-dollhouse-design.md` §3.6, §8 step 5. Ticket #22.
All paths are relative to `office/` unless they start with `work/` or `server/`. Gate per task:
`mise run office:check` green before the next task starts (tests: `cd office && bun test test/<file>`).
One commit per task. Ship as **small stacked PRs** (`gh stack`, rebase only): PR A = tasks 1–3
(header), PR B = tasks 4–6 (life card), then the blocked PRs C–E (outline at the end).

## What exists, what blocks what

| Need | State | Consequence |
|---|---|---|
| Server `Server.Life`, `/api/life/:ws…`, snapshot `life` block | **Step 4, #133 — branch `work/home-life-routines`, in verify, not on main** | Tasks 1–6 code against its wire shapes (below) and stand on a fake server in tests, so they can be written and merged-ready now; **PR A/B must not merge before #133 does** (rebase onto main once it lands; then run the live check in task 6). |
| `home` workspaces | `workspaces.type = "home"` arrives with #133 (the TUI already offers `life` as a type at `tui/main.ts:865`; #133 widens it) | The header/card show only for a workspace that has a `life` entry in the snapshot — no type sniffing in the client. |
| Home tile **rendering** (routines in their tiles, fridge, living-room wall, trophy shelf) | `kit/home.ts` + build mode only edit `home.json`; **no home tile has art or spots yet** (`kit/tiles/` holds only office tiles; #176 garden is just a catalogue kind) | Tasks 7–9 are **blocked on a "home tiles draw" step** that nobody has planned. Outlined, not detailed. |
| Clock-in/out walk | Needs the home tiles *and* a second floor/viewport target | Blocked on the same; last. |

Ask for the operator if undecided: who owns the missing "home tiles draw" step (it is the real
critical path for the room half of step 5).

### Wire shapes (from #133's spec, §3/§4/§6) — the contract these tasks code against

```
GET /api/office            → …, life: { "<ws id>": { level, xp, due: Due[] } }   // only type:"home" workspaces
GET /api/life/:ws          → { xp, level, next_level_at, streaks: {"<routine id>": n}, due: Due[],
                               quests: Quest[], today: Today[] }
POST /api/life/:ws/routines   {title, every, window_minutes?, xp?, tile?}  → 201 routine
POST /api/life/:ws/quests     {title, due_at?, xp?}                         → 201 quest
POST /api/life/routines/:id/done → { run, level_up: bool }
POST /api/life/quests/:id/done   → { quest, level_up: bool }
Due   = { routine_id, title, due_at: iso, window_remaining: seconds }   // negative = past its window (overdue)
Quest = { id, title, due_at: iso|null, xp }
Today = { routine_id, title, due_at: iso, done: bool }
```
Level math (server's, mirrored for the bar only): `level = floor(sqrt(xp/100))`, so level L starts at
`100·L²` xp and `next_level_at = 100·(L+1)²`. If #133's final `next_level_at` differs, the bar
uses the server's value — it never recomputes the threshold.

---

## Task 1 — the life types and the bar (pure, `kit/life.ts`)

**Files**: `test/life.test.ts` (new), `kit/life.ts` (new), `kit/types.ts` (edit).

Test first (`test/life.test.ts`):
```ts
import { describe, expect, test } from "bun:test"
import { lifeBar, lifeHeader } from "../kit/life"
import { EMPTY } from "../kit/types"

describe("lifeBar", () => {
  // level 2 starts at 400, level 3 at 900 (100·L²): 650 is halfway through level 2
  test("empty at the start of a level", () => expect(lifeBar(400, 400, 900)).toBe("▱▱▱▱▱"))
  test("half-way rounds down to 2 of 5", () => expect(lifeBar(650, 400, 900)).toBe("▰▰▱▱▱"))
  test("full just before the next level, never over", () => expect(lifeBar(899, 400, 900)).toBe("▰▰▰▰▰"))
})
describe("lifeHeader", () => {
  const a = { ...EMPTY, life: { "7": { level: 2, xp: 650, due: [{ routine_id: 1, title: "teeth", due_at: "2026-10-08T07:00:00Z", window_remaining: 600 }] } } }
  test("level, bar, due count — for a workspace that has a life entry", () =>
    expect(lifeHeader(a, 7)).toBe("lv 2 ▰▰▱▱▱ · 1 due"))
  test("nothing due says so", () =>
    expect(lifeHeader({ ...a, life: { "7": { level: 2, xp: 650, due: [] } } }, 7)).toBe("lv 2 ▰▰▱▱▱ · all done"))
  test("a workspace with no life entry has no header", () => {
    expect(lifeHeader(a, 8)).toBeNull()
    expect(lifeHeader(a, null)).toBeNull()
  })
})
```
Run: `bun test test/life.test.ts` → red (module missing).

Then `kit/life.ts`:
```ts
// The life side as the office draws it: pure views over the snapshot's `life` block (Server.Life).
import type { Agents, Due } from "./types"

/** level L starts at 100·L² xp (the server's curve); the bar only draws progress, never decides a level */
const levelStart = (level: number) => 100 * level * level

/** five cells for the way from `start` to `next` xp */
export function lifeBar(xp: number, start: number, next: number): string {
  const f = next > start ? Math.min(1, Math.max(0, (xp - start) / (next - start))) : 0
  const n = Math.min(5, Math.floor(f * 5))
  return "▰".repeat(n) + "▱".repeat(5 - n)
}

export const dueCount = (due: Due[]) => due.length

/** `lv 7 ▰▰▰▱▱ · 3 due`, or null where the workspace has no life side */
export function lifeHeader(a: Agents, ws: number | null): string | null {
  const l = ws === null ? undefined : a.life?.[String(ws)]
  if (!l) return null
  const start = levelStart(l.level), next = levelStart(l.level + 1)
  return `lv ${l.level} ${lifeBar(l.xp, start, next)} · ${l.due.length ? `${l.due.length} due` : "all done"}`
}
```
(Drop `dueCount` if nothing else uses it by task 6 — YAGNI.)

`kit/types.ts` — add above `Agents` and one optional field in it:
```ts
/** a routine whose current due is unmet; `window_remaining` seconds, negative once past its window */
export type Due = { routine_id: number; title: string; due_at: string; window_remaining: number }
/** a workspace's life summary on the snapshot (`Server.Life.status`, trimmed); full detail is `GET /api/life/:ws` */
export type LifeSummary = { level: number; xp: number; due: Due[] }
```
and inside `Agents` after `flags?`:
```ts
  /** the life side per `home` workspace id (`Server.Office.status`); absent for every other workspace */
  life?: Record<string, LifeSummary>
```
**Done**: `bun test test/life.test.ts` green; `bunx tsc --noEmit` (via `mise run office:check`) clean.
Commit: `life: lifeBar and lifeHeader over the snapshot's life block`.

## Task 2 — `data.status()` passes `life` through

**Files**: `test/data.test.ts` (edit), `tui/data.ts` (edit).

Test first — change the stand-in server's snapshot in `test/data.test.ts` to include
`life: { "7": { level: 2, xp: 650, due: [] } }` and add to the existing test (or a new one beside it):
```ts
  expect(all.life).toEqual({ "7": { level: 2, xp: 650, due: [] } })
```
Run `bun test test/data.test.ts` → red (`status()` drops unknown keys).

In `tui/data.ts`'s `status()` return object, append `life: j.life ?? {}` after `flags: j.flags ?? {}`.
**Done**: `bun test test/data.test.ts` green. Commit: `life: carry the snapshot's life block through data.status`.

## Task 3 — the XP bar in the header

**Files**: `tui/main.ts` (edit, one segment).

The header line is built in `draw()` at the `// header:` comment (`line([ …OFFICE badge, wsName, needs… ])`).
Add `import { lifeHeader } from "../kit/life"` and insert, right after the `...(needs.length ? [dim("  (i)")] : [])` line:
```ts
    ...(lifeHeader(all, ws) ? [{ s: `  ${lifeHeader(all, ws)}`, fg: ROLE.body }, dim("  (L)")] : []),
```
(`ws` is the open workspace id; `all` the snapshot. `(L)` advertises the card from task 4.)
Colour is a `ROLE`, text is not colour-only (glyph bar + words) — WCAG law holds.

No unit test beyond task 1's (the line builder isn't separable and `lifeHeader` carries the logic);
verify by driving: run the `drive-office` skill against a stand-in server, or against the live one after
#133 merges — pick a `home` workspace and read the header back. **Done**: `mise run office:check` green and the
driven header reads `lv N ▰▰▱▱▱ · M due`; on an office workspace there is no life segment.
Commit: `life: XP bar and due count in the header`. **→ PR A.**

## Task 4 — data calls for the card

**Files**: `test/data.test.ts` (edit), `tui/data.ts` (edit).

Test first, extending the stand-in server to route `GET /api/life/7` →
`{ xp: 650, level: 2, next_level_at: 900, streaks: { "1": 3 }, due: [{routine_id:1,title:"teeth",due_at:"2026-10-08T07:00:00Z",window_remaining:600}], quests: [{id:5,title:"book dentist",due_at:null,xp:20}], today: [] }`
and `POST /api/life/routines/1/done` → `{ run: {}, level_up: true }`:
```ts
test("life reads the card's body and a stamp reports a level-up", async () => {
  const data = await import("../tui/data")
  expect((await data.life(7))?.level).toBe(2)
  expect(await data.routineDone(1, "teeth")).toContain("level up")
})
```
(Fetch handler: match on `pathname` and method; keep the existing `/office` branch.) Run → red.

`tui/data.ts` additions (patterns: `read`, `write` already exist):
```ts
export type LifeStatus = { xp: number; level: number; next_level_at: number; streaks: Record<string, number>; due: Due[]; quests: LifeQuest[]; today: { routine_id: number; title: string; due_at: string; done: boolean }[] }
export type LifeQuest = { id: number; title: string; due_at: string | null; xp: number }
/** a home workspace's life card body */
export const life = (ws: number) => read<LifeStatus>(`/life/${ws}`)
/** stamp a routine done; says so, and shouts a level-up */
export const routineDone = (id: number, title: string) =>
  write(`stamping ${title}`, `/life/routines/${id}/done`, {}, (j) => `${title} done${j.level_up ? " — level up!" : ""}`)
export const questDone = (id: number, title: string) =>
  write(`finishing ${title}`, `/life/quests/${id}/done`, {}, (j) => `${title} done${j.level_up ? " — level up!" : ""}`)
export const routineNew = (ws: number, title: string, every: string) =>
  write("adding the routine", `/life/${ws}/routines`, { title, every }, (j) => `added ${j.title}`)
export const questNew = (ws: number, title: string) =>
  write("adding the quest", `/life/${ws}/quests`, { title }, (j) => `added ${j.title}`)
```
Import `Due` from `../kit/types`. **Done**: `bun test test/data.test.ts` green.
Commit: `life: data calls for /api/life`.

## Task 5 — the card's rows as a pure view

**Files**: `test/life.test.ts` (edit), `kit/life.ts` (edit).

Test first — what the card lists, soonest-first, overdue marked, with the streak:
```ts
import { lifeRows } from "../kit/life"
describe("lifeRows", () => {
  const s = { xp: 650, level: 2, next_level_at: 900, streaks: { "1": 3 },
    due: [{ routine_id: 2, title: "stretch", due_at: "2026-10-08T09:00:00Z", window_remaining: -60 },
          { routine_id: 1, title: "teeth", due_at: "2026-10-08T07:00:00Z", window_remaining: 600 }],
    quests: [{ id: 5, title: "book dentist", due_at: null, xp: 20 }], today: [] }
  test("due routines first (overdue flagged), then open quests", () => {
    expect(lifeRows(s).map((r) => [r.kind, r.id, r.text])).toEqual([
      ["routine", 2, "stretch · overdue"],
      ["routine", 1, "teeth · 10m left · streak 3"],
      ["quest", 5, "book dentist · +20 xp"],
    ])
  })
})
```
Note order: overdue (negative remaining) sorts before positive, then ascending `window_remaining`.
Run → red. Implement in `kit/life.ts`:
```ts
import type { LifeStatus } from "./types"
export type LifeRow = { kind: "routine" | "quest"; id: number; text: string }
const left = (s: number) => (s < 0 ? "overdue" : s < 3600 ? `${Math.ceil(s / 60)}m left` : `${Math.floor(s / 3600)}h left`)
export function lifeRows(s: LifeStatus): LifeRow[] {
  const due = [...s.due].sort((a, b) => a.window_remaining - b.window_remaining).map((d): LifeRow => {
    const streak = s.streaks[String(d.routine_id)] ?? 0
    return { kind: "routine", id: d.routine_id, text: `${d.title} · ${left(d.window_remaining)}${streak ? ` · streak ${streak}` : ""}` }
  })
  return [...due, ...s.quests.map((q): LifeRow => ({ kind: "quest", id: q.id, text: `${q.title} · +${q.xp} xp` }))]
}
```
`kit/` never imports `tui/`: define `LifeStatus`/`LifeQuest` (as written in task 4) in `kit/types.ts` and have `tui/data.ts` import them from there — move them in this commit.
**Done**: `bun test test/life.test.ts` green. Commit: `life: lifeRows, the card's rows as a pure view`.

## Task 6 — the life card (`L`)

**Files**: `tui/main.ts` (edit).

Follow the `calendar` card exactly (it is the nearest pattern):
1. `Mode` union (line ~37): add `| { kind: "life" }`.
2. State beside `cal`: `let lifeCard: data.LifeStatus | null = null`.
3. `loadCard()` switch (~line 208): `case "life": lifeCard = (await data.life(w)) ?? lifeCard; break`.
4. `detail()` switch: new case, rows from `lifeRows`, Enter on a row stamps it:
   ```ts
   case "life": {
     const s = lifeCard
     const rows: Row[] = s ? lifeRows(s).map((r) => ({
       segs: [plain(r.text)],
       open: () => void did(r.kind === "routine" ? data.routineDone(r.id, r.text.split(" · ")[0]!) : data.questDone(r.id, r.text.split(" · ")[0]!)).then(loadCard).then(draw),
     })) : []
     return {
       title: s ? `LIFE · lv ${s.level} · ${s.xp} xp` : "LIFE",
       rows,
       actions: [
         { key: "r", label: "new routine", run: newRoutine }, { key: "q", label: "new quest", run: newQuest }, back1,
       ],
     }
   }
   ```
5. `newRoutine()` / `newQuest()` beside `newSchedule`: `ask("routine — what, then how often", …)` collecting a title, then `ask("every — a cron or @daily/@weekly", (every) => did(data.routineNew(w, title, every.trim())).then(loadCard).then(draw))`; quest: one `ask` for the title.
6. Key dispatch (~line 1305, next to `case "B"`): `case "L": if (all.life?.[String(ws)]) open({ kind: "life" }); return`. Only on a workspace with a life entry; add `L` to the home foot keys list in `detail()`'s `home` case gated the same way.
7. `refresh()` already reloads the open card via `loadCard`, so a stamp from elsewhere shows within a poll.

**Done** (run, don't assume): `mise run office:check` green, then `drive-office` skill: open a `home`
workspace, press `L`, read the card back, `⏎` a due routine, read the status line (`teeth done`), then
`curl $TLON_URL/api/life/<ws>` shows the run (the due is gone, `xp` up) — this is the ticket's check.
Needs #133 live; before that, drive against the stand-in server from tasks 2/4.
Commit: `life: the life card — due and quests, stamp, add`. **→ PR B.**

---

## Blocked — outline only (plan these when their blocker lands)

**Prerequisite step (unowned): home tiles draw.** `kit/tiles/` needs `living`, `kitchen`, `bathroom`, `bedroom`,
`street` tiles (`Tile<L>` with `blocks`/`spots`/`draw`, as `kit/tiles/kitchen.ts` does), a `floorPlan` fed by
`loadHome()`, and the viewport reaching them (Floor steps 2–3). Without it nothing below can be drawn.

**PR C — routines in their tiles (blocked on the prerequisite + #133).**
`Due.tile`/`today` need the routine's `tile` on the wire (server: add `tile` to the `due` entry — a one-line
change to #133's `due/2`). `draw()` of each home tile reads `a.life[ws].due` and, for routines whose `tile`
matches, draws the glint at a per-routine anchor and `glow`s (2 s sine) while due; late (negative
`window_remaining`) puts the cat on it. Click/`⏎` on the anchor calls `data.routineDone` — the same write as the
card. Test: golden-pixel diff on a due vs done routine; a `Hit` exists per due anchor; driven stamp as in task 6.

**PR D — fridge, wall calendar, trophy shelf (blocked on the prerequisite).** Fridge = `Server.Note` scoped to the
home workspace (`data.note`/notes already exist; draw the home ws's notes on the kitchen tile). Wall calendar:
move the draw out of `wide.ts`'s back wall into a shared function the living tile calls, with `.ics` dots from
`Server.Calendar` (check what it exposes before planning). Trophy shelf: pure function of `streaks`/`level` →
trophies (7/30/100, per level), never stored; needs `streaks` from `GET /api/life/:ws` (poll when the room is on
a home workspace). Level-up: `Party` (as `wide.ts`) on a `level_up` response, plus a `CorkNote` from the cat.

**PR E — clock-in/out walk (blocked on the prerequisite).** `home.json` gains `clock_out`/`clock_in`; keys
`h`/`o` jump the viewport and fast-walk the figure; attention-driven walks (open a thread → office, stamp/card →
home). Check: "the walk is seen, not assumed" — `drive-office`, capture frames mid-walk. Biggest of the lot;
plan it after PR D and split by trigger (keys first, clock last).

## Risks / open

- Do not merge A/B before #133 is on main; if #133's wire differs from the table above, adjust task 1/4 types only.
- `kit/` must not import from `tui/` (task 5 note) — the `Due`/`LifeStatus` types live in `kit/types.ts`.
- Overdue routines stay on the due list (negative remaining), per #133's spec; the card shows `overdue`.
- No routine packs, no edit/pause of routines from the card (YAGNI; PATCH route exists if wanted later).
