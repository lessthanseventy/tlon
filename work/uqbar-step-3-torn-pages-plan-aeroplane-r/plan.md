# Uqbar step 3 — torn pages: plan (ticket #48)

Spec: `docs/plans/2026-10-08-uqbar-design.md` §3, §7 step 3. Two worklines, **do not merge them**:
**A** = the aeroplane (office-only); **B** = the release-cut TV channel (server → office; the
server surface gets the riskier review). A and B touch disjoint files except one line each in
`office/tui/main.ts` and `office/rooms/wide.ts` (see "Overlap").

Run everything through mise: `mise run office:test`, `mise run server:test`, `mise run check`.

## Decisions (settled here, with the evidence)

1. **B's signal is a new read endpoint, not `release:status`.** `Server.Release.PM.cut/4`
   (`server/lib/server/release/pm.ex:185`) already records the cut durably as an event on the
   root thread: `kind: "check_passed"`, `correlation: "release:<sha>"`,
   `detail: {"cmd":"release cut","from","to","changelog"}`. `release:status` shells out to git and
   the gate — wrong for a 2 s office poll. The office's `/api/office/activity/:ws` already carries
   that row but flattens `detail` to `"release cut"` (`room.ex event_text/1`), dropping the changelog.
   → add `GET /api/office/release/:ws` → `Room.release/1` → `%{sha, changelog, at} | null`.
2. **"Until the restart" = event `at` is newer than the server's boot.** `/api/office/health`
   already returns `up_s` (VM uptime, `Room.health/0`). Pending cut ⇔ `at > now − up_s`. No git, no
   new server state. After the restart the TV returns to its rotation by itself.
3. **Lead-of-thread lookup is already in the snapshot**: `Thread.lead?: string | null`
   (`office/kit/types.ts:14`, server `Channel.thread_lead/1`). Desk target = the actor whose
   `seat.agent === lead`; no lead, or no actor in the room → the thread's whiteboard card perch
   (`WideRoom.cards`, the same fallback `goalOf` uses); no card → `boardEdge`.
4. **Post signal = the activity feed, no server change.** A `uqbar` post is a feed row
   `{kind:"message", who:"uqbar", thread_id, at, text}` (`Room.activity`, `main.ts loadFeed`).
   Dedupe with the same `${at}${kind}${text}` key `loadFeed` already uses; the first load plays
   nothing (history is not news).
5. **Hand-off gap — flagged, not fixed here.** Nothing writes `handoff_opened`
   (grep `server/lib`: only the DB CHECK lists it) and `Channel.assign_lead` leaves no record of
   old→new lead. The snapshot's `visits` *does* carry staffing hand-offs
   (`Server.Office.visits/0`: parent thread's lead → child's lead, last few minutes). A's hand-off
   flight rides `visits` (old=`from`, new=`to`) **only while a uqbar session is live** (`a.uqbar`).
   A true lead *reassignment* needs a server event — file as its own ticket, out of step 3.
6. **Scope fence kept**: no dog-ear on the post, no Nina swat (step 6 / #51). Argos catching is sim
   only: the plane is delayed, the message still lands, nothing about the post changes.
7. **Golden must NOT move** for A or B. With no uqbar post and no cut, nothing new is drawn and no
   RNG is consumed (the TV's start channel is already `Math.random` — don't add draws before it). A
   test asserts the hash is unchanged; `mise run office:golden` is a smell, not a step.

---

# Workline A — the aeroplane (senior; office kit sim/render)

Files: new `office/kit/plane.ts`, new `office/test/plane.test.ts`; edits `office/rooms/wide.ts`,
`office/tui/main.ts`. Base: `kit/uqbar.ts` (`Pt`, `Book`, `stepBook`, `drawBook`). Land as 5 commits.

### A1 — the flight, pure (`office/kit/plane.ts`)

Test first, `office/test/plane.test.ts`:

```ts
import { describe, expect, test } from "bun:test"
import { FOLD, TEAR, UNFOLD, caughtNth, freshPosts, launch, stepPlane, type Plane } from "../kit/plane"

const run = (p: Plane | null, max = 500) => { const seen: Plane[] = []; while (p && seen.length < max) { seen.push(p); p = stepPlane(p) } return seen }

describe("the paper aeroplane", () => {
  test("tears, folds, glides along its legs, unfolds, then is gone", () => {
    const s = run(launch({ x: 0, y: 0 }, [], { x: 30, y: 0 }))
    expect(s[0]!.phase).toBe("tear")
    expect(s.filter((p) => p.phase === "tear").length).toBe(TEAR)
    expect(s.filter((p) => p.phase === "fold").length).toBe(FOLD)
    expect(s.filter((p) => p.phase === "unfold").length).toBe(UNFOLD)
    const last = s.filter((p) => p.phase === "glide").at(-1)!
    expect(last.at).toEqual({ x: 30, y: 0 })
  })
  test("a hand-off passes over the old lead on the way: one flight, two legs", () => {
    const via = { x: 10, y: 40 }
    const s = run(launch({ x: 0, y: 0 }, [via], { x: 60, y: 0 }))
    expect(s.some((p) => p.phase === "glide" && p.at.x === 10 && p.at.y === 40)).toBe(true)
    expect(run(launch({ x: 0, y: 0 }, [], { x: 60, y: 0 })).length).toBeLessThan(s.length)
  })
  test("a leg with a hold stays put that many ticks (Argos has it)", () => {
    const held = run(launch({ x: 0, y: 0 }, [{ x: 12, y: 0, hold: 20 }], { x: 30, y: 0 }))
    const free = run(launch({ x: 0, y: 0 }, [{ x: 12, y: 0 }], { x: 30, y: 0 }))
    expect(held.length - free.length).toBe(20)
  })
  test("Argos catches every 4th plane, deterministically", () => {
    expect([0, 1, 2, 3, 4, 7].map(caughtNth)).toEqual([false, false, false, true, false, true])
  })
})

describe("freshPosts", () => {
  const row = (at: string, who: string | null, kind = "message", thread_id: number | null = 7) => ({ kind, at, thread_id, who, text: "x" })
  test("only uqbar's messages, only unseen, oldest first; the first load plays nothing", () => {
    const feed = [row("3", "uqbar"), row("2", "andrew"), row("1", "uqbar"), row("0", "uqbar", "fact")]
    const seen = new Set<string>()
    expect(freshPosts(feed, seen, true)).toEqual([])
    expect(freshPosts(feed, seen, false)).toEqual([])           // already seen on the first load
    expect(freshPosts([row("4", "uqbar"), ...feed], seen, false).map((x) => x.at)).toEqual(["4"])
    expect(freshPosts([row("4", "uqbar"), ...feed], seen, false)).toEqual([])
  })
  test("a post with no thread has nowhere to fly", () => {
    expect(freshPosts([row("9", "uqbar", "message", null)], new Set(), false)).toEqual([])
  })
})
```

Code, `office/kit/plane.ts`:

```ts
// A uqbar post as a paper aeroplane (docs/plans/2026-10-08-uqbar-design.md §3): a page tears out of
// the book, folds, glides leg by leg to its recipient, unfolds. Pure: the room owns where legs are.
import type { Pt } from "./uqbar"

export type Phase = "tear" | "fold" | "glide" | "unfold"
export type Leg = Pt & { hold?: number }
/** `at`: where it is; `t`: ticks in this phase; `legs`: still to fly; `hold`: ticks left to wait at the leg it reached */
export type Plane = { phase: Phase; t: number; at: Pt; legs: Leg[]; hold: number }
export const TEAR = 6, FOLD = 8, UNFOLD = 10, SPEED = 3

export const launch = (from: Pt, via: Leg[], to: Pt): Plane => ({ phase: "tear", t: 0, at: from, legs: [...via, to], hold: 0 })

/** one tick; null once it has unfolded */
export function stepPlane(p: Plane): Plane | null {
  switch (p.phase) {
    case "tear": return p.t + 1 >= TEAR ? { ...p, phase: "fold", t: 0 } : { ...p, t: p.t + 1 }
    case "fold": return p.t + 1 >= FOLD ? { ...p, phase: "glide", t: 0 } : { ...p, t: p.t + 1 }
    case "unfold": return p.t + 1 >= UNFOLD ? null : { ...p, t: p.t + 1 }
    case "glide": {
      if (p.hold > 0) return { ...p, hold: p.hold - 1 }
      const [leg, ...rest] = p.legs
      if (!leg) return { ...p, phase: "unfold", t: 0 }
      const dx = leg.x - p.at.x, dy = leg.y - p.at.y, d = Math.hypot(dx, dy)
      if (d <= SPEED) return { ...p, at: { x: leg.x, y: leg.y }, legs: rest, hold: leg.hold ?? 0 }
      return { ...p, at: { x: p.at.x + (dx / d) * SPEED, y: p.at.y + (dy / d) * SPEED } }
    }
  }
}

/** Argos catches every 4th plane of the room's life: no dice, so a seeded test sees the same dog */
export const caughtNth = (n: number) => n % 4 === 3

export type FeedRow = { kind: string; at: string; thread_id: number | null; who: string | null; text: string }
/** the feed's uqbar posts not seen yet, oldest first; marks every row seen. `first`: history, not news */
export function freshPosts(feed: FeedRow[], seen: Set<string>, first: boolean): FeedRow[] {
  const out: FeedRow[] = []
  for (const x of feed) {
    const k = `${x.at}${x.kind}${x.text}`
    if (seen.has(k)) continue
    seen.add(k)
    if (!first && x.kind === "message" && x.who === "uqbar" && x.thread_id !== null) out.push(x)
  }
  return out.reverse()
}
```

Note the hold-test arithmetic: a hold of 20 at leg 1 adds exactly 20 glide ticks (the `hold>0`
branch), so `held − free = 20`.

Done: `cd office && bun test test/plane.test.ts` green (and red before the file exists).
Commit: `office: the uqbar aeroplane's flight, pure`.

### A2 — draw it (`office/kit/plane.ts` `drawPlane`, `office/test/plane.test.ts`)

Test first (append): `FRAMES.sheet|folded|plane|unfold` rows are rectangular, ≤ 8 wide, and match
`/^[.pk w]+$/`-style paint like `uqbar.test.ts` "every frame is rectangular". Then add the frames
(`p` page, `k` ink, `w` ribbon-edge), and

```ts
export function drawPlane(sc: Scene, p: Plane) { /* pick FRAMES by phase (tear → sheet, fold → folded
  by t, glide → plane, unfold → unfold by t); sc.overhead.push(() => sc.blit([...frame], x, y, paint)) */ }
```
using `sc.overhead` and `sc.blit` exactly as `drawBook` does (`kit/uqbar.ts`), paint `{p: ROLE.prose, k: ROLE.fieldInk, w: ROLE.body}`. Legibility rule (operator has XLRS): ≥ 6 px wide,
2-colour only, no 1-px-detail; glide frame alternates 2 frames with `sc.tick >> 1` like the book's flap.
Done: `mise run office:test` green. Commit: `office: draw the uqbar aeroplane`.

### A3 — the room flies it (`office/rooms/wide.ts`)

Test first (`office/test/uqbar.test.ts`, new `describe("torn pages")`, uses `office(3)`/`viewOf` +
`withUqbar` from that file): build `new WideRoom(640)`, `room.fly(101)` (thread 101's lead is `w0`…
check `office()` in `test/golden.ts`: thread `100+i` is led by `names[i]`); step the room until
`room.planes.length === 0`; assert (a) a plane existed, (b) at its last glide tick its `at` equals the
lead actor's position (`actors.get(...)`), (c) `fly(<thread with lead:null>)` ends on `cards.get(tid)`,
(d) **`frameHashes()` equals `golden.json` with no plane in flight** (the no-churn guard).

Code: in `WideRoom` add `private planes: Plane[] = []`, `private flights = 0`, and

```ts
/** a uqbar post to thread `tid`: a page tears out of the book and flies to its lead's desk, else its card */
fly(tid: number, a: Agents, via: Pt[] = []) {
  const lead = a.threads.find((t) => t.id === tid)?.lead
  const who = lead ? [...this.actors.values()].find((x) => x.seat.agent === lead) : undefined
  const to = who ? { x: who.x, y: who.y - 10 } : this.cards.get(tid) ?? this.boardEdge
  this.planes.push(launch({ x: this.book.x, y: this.book.y }, via, to))
  this.changed = true
}
```
`step()` (wide.ts:242): add `this.stepPlanes()` to the `[...].some(Boolean)` list, which maps
`stepPlane`, drops null, returns `planes.length > 0`. `draw()`: `for (const p of this.planes) drawPlane(sc, p)`
next to `drawBook` (wide.ts:343). The room has no snapshot at `fly` time → pass `a` from main.ts.
Done: `mise run office:test` green incl. golden. Commit: `office: a uqbar post flies to its lead's desk`.

### A4 — wire the feed + the hand-off (`office/tui/main.ts`, `office/rooms/wide.ts`)

Test first, in `plane.test.ts`: `handoffVia(visits, a)` (pure, exported from `kit/plane.ts`) — given
`visits: Visit[]` (`{from,to,workspace_id,at}`, `kit/types.ts`) and a uqbar-live `Agents`, returns the
`via` waypoint = old lead's actor position for the freshest handoff visit within 60 s, else `[]`;
returns `[]` when `a.uqbar` is null (no session ⇒ no hand-off flight; design decision 5).
Wire: in `loadFeed()` (main.ts:288) keep a module-level `const flown = new Set<string>()`:

```ts
for (const x of freshPosts(feed, flown, first)) room().fly(x.thread_id!, all, handoffVia(all.visits, all))
```
Do **not** reuse `seen` (it is rebuilt each call). Done: manual — `mise run office:drive` with a seeded
feed row, plus `bun test` green. Commit: `office: uqbar posts and hand-offs fly`.

### A5 — Argos chases (`office/rooms/wide.ts`, `office/kit/pets.ts`)

Test first (`uqbar.test.ts`, wrapped in `seeded(1, …)` from `test/golden.ts`): launch 4 planes via
`fly`; the 4th has a `hold` leg and Argos' `dog.path` is non-empty/leads toward it while it is in the
air; its message still lands (plane list empties, no dog-ear, post data unchanged); planes 1–3 have no
hold leg. Code: in `fly`, `if (caughtNth(this.flights++))` insert a `{x,y,hold: 24}` leg at the
midpoint of from→to and send Argos there with the same `route` call `dogDo` uses
(`this.plan.route(d.x, d.aisle, spot)`, wide.ts:178). Argos' existing `stepDog` ends his path as
`mode:"sit"`; say `this.argos("cheer", …)`-style line is optional — YAGNI, skip it.
Done: `mise run office:test` + `mise run check`. Commit: `office: Argos chases the aeroplane and sometimes catches it`.

---

# Workline B — the release-cut TV channel (senior; server → office)

Files: `server/lib/server/office/room.ex`, `server/lib/server/mcp/operator_api.ex`,
`server/test/server/office/room_test.exs`, `office/tui/data.ts`, `office/kit/tv.ts`,
`office/rooms/wide.ts`, `office/tui/main.ts`, `office/test/tv.test.ts`, `office/test/data.test.ts`.
B1–B2 are the risky server surface: read-only, one new GET, no schema change, no migration.

### B1 — `Room.release/1`

Test first, `server/test/server/office/room_test.exs` (setup gives `ws`, `other`, `t`):

```elixir
test "release: the newest cut on the workspace's threads; nil with none; never another's", ctx do
  assert Room.release(ctx.ws.id) == nil
  {:ok, far} = Channel.open_thread(%{title: "far", workspace_id: ctx.other.id})
  cut = fn thread, sha, log ->
    Dossier.record_event(%{thread_id: thread.id, kind: "check_passed", correlation: "release:#{sha}",
      detail: %{"cmd" => "release cut", "exit" => 0, "from" => "a", "to" => sha, "changelog" => log}})
  end
  {:ok, _} = cut.(far, "ffff", "elsewhere")
  assert Room.release(ctx.ws.id) == nil
  {:ok, _} = cut.(ctx.t, "650fa4a1", "1. Intake works the board's top first.")
  {:ok, _} = Dossier.record_check(%{thread_id: ctx.t.id, exit: 0, cmd: "mix test"})
  assert %{sha: "650fa4a1", changelog: "1. Intake works the board's top first.", at: %DateTime{}} = Room.release(ctx.ws.id)
end
```

Code, in `room.ex` next to `activity/2` (needs the file's existing `Event`, `Thread`, `Repo`, `from`):

```elixir
@doc """
The newest release cut recorded on a workspace's threads (`Server.Release.PM.cut/4` writes it as a
`check_passed` event, correlation `release:<sha>`), `%{sha, changelog, at}`, or nil. The office
shows its changelog on the TV until the service next restarts.
"""
@spec release(integer()) :: map() | nil
def release(workspace_id) do
  ids = from(t in Thread, where: t.workspace_id == ^workspace_id, select: t.id)

  from(e in Event,
    where: e.thread_id in subquery(ids) and e.kind == "check_passed" and like(e.correlation, "release:%"),
    order_by: [desc: e.id],
    limit: 20
  )
  |> Repo.all()
  |> Enum.find_value(fn
    %Event{detail: %{"cmd" => "release cut"} = d, created_at: at} -> %{sha: d["to"], changelog: d["changelog"], at: at}
    _ -> nil
  end)
end
```
(`like/2` filter + Elixir match on `cmd`: `detail` is a `Server.JSONColumn`, so don't query into it.)
Done: `mise run server:test -- test/server/office/room_test.exs`. Commit: `office: Room.release, the newest cut`.

### B2 — the route

Test first, in the existing operator-api test (find with `grep -rn "office/triage" server/test`): GET
`/api/office/release/<ws>` → 200 `null` with no cut, and the `%{sha, changelog, at}` body after one.
Code, `operator_api.ex:311`: add `release` to `~w(activity triage memory tickets board workspace schedules)`
(it dispatches `apply(Room, String.to_existing_atom(read), [ws.id])`), and add the route line to the
moduledoc table (line ~30):
`GET /api/office/release/:ws  Office.Room.release (the newest release cut: sha, changelog, at)`.
Done: `mise run server:test` green; `mise run server:check` (names + manual). Commit: `office: GET /api/office/release/:ws`.

### B3 — the TV channel (`office/kit/tv.ts`)

Test first, `office/test/tv.test.ts` (follow the existing `showLevel` test): 

```ts
test("the entry channel holds the screen until it is released, then the rotation resumes", () => {
  const tv = new Tv(48, 28)
  tv.showEntry("650fa4a", "Intake works the board's top first. Cuts are quiet.")
  expect(tv.channel).toBe("entry")
  for (let i = 0; i < 1000; i++) tv.step()           // longer than the 300-frame rotation
  expect(tv.channel).toBe("entry")
  tv.next()                                          // a click must not drop the entry either
  expect(tv.channel).toBe("entry")
  tv.clearEntry()
  expect(tv.channel).not.toBe("entry")
})
test("the entry draws: header and a marquee line light dots, and the marquee moves", () => { /* two
  steps 6 frames apart differ in dots rows ≥ 20; the header rows are identical */ })
```
Code: add `private entry: { sha: string; text: string } | null = null`, a `drawText`-based render
(48×28 dot screen, `SMALL` 6×9: only 8 glyphs a row — header rows `UQBAR` (y 2) and `XLVI` (y 12) are
static, the changelog is a one-row **marquee** at y 21 scrolling `text` right-to-left by one dot per
frame, `drawText`'s centering replaced by an x offset). `channel` getter returns `"entry"` while set;
`step()` renders it before the level/rotation branches; `next()` is a no-op while set; `showEntry` /
`clearEntry` set/clear and `clear()` the screen. Full changelog is still readable: the TV hit's `tip`
(wide.ts:677) shows `entry.text` (B4). Done: `mise run office:test`. Commit: `office: the TV's encyclopedia entry channel`.

### B4 — wire it (`office/tui/data.ts`, `office/tui/main.ts`, `office/rooms/wide.ts`)

Test first, `office/test/data.test.ts` (existing fake-server pattern): `data.release(ws)` GETs
`/office/release/<ws>` and returns `{sha, changelog, at}` or `null`. Then:

```ts
// data.ts, beside activity
export type Cut = { sha: string; changelog: string; at: string } | null
/** the newest release cut in a workspace (the TV's entry), null with none */
export const release = (ws: number) => read<Cut>(`/office/release/${ws}`)
```
`wide.ts`: `tvEntry(entry: { sha: string; text: string } | null)` calls `tvSet.showEntry|clearEntry`
(idempotent: same sha ⇒ no re-init, or the marquee restarts every poll); the TV hit's `tip` reads
`the TV: UQBAR — release ${sha}. ${text}` while an entry is up. `main.ts`: in the loop that already
refreshes `rack` (health) call `data.release(ws)` and set
`room().tvEntry(cut && Date.parse(cut.at) > Date.now() - rack.up_s * 1000 ? { sha: cut.sha.slice(0,7), text: cut.changelog } : null)`.
`rack === null` (health unread) ⇒ show nothing — never guess pending. Done: unit tests +
`mise run office:drive` once with a stubbed server cut (note in the PR, "unverified live until a real cut").
Commit: `office: the TV shows the release cut until the restart`.

### B5 — gate

`mise run check` (names + server + adapters + office + manual). Confirm the golden is unchanged
(`git diff --stat office/test/golden.json` empty). If the manual lists HTTP routes
(`docs/manual/`), `server:check` will say so — add the route there.

---

## Overlap A↔B and merge order

`main.ts` (A4 in `loadFeed`; B4 in the rack refresh) and `wide.ts` (A3 `fly`/`step`/`draw`; B4
`tvEntry`/TV hit) — different hunks, separate commits. Either lands first; the second rebases (the
`office/test/home.test.ts` union-the-imports bounce, fact #665, is the thing to expect). A and B
share no test file.

## Open (named, not fixed)

- **Lead reassignment leaves no record** (decision 5): file a Tlön ticket, "assign_lead writes a
  `handoff_opened` event with old/new lead", then A's `handoffVia` reads that instead of `visits`.
- **Plane lands where the lead is, not necessarily at the desk**, when they're away (coffee,
  couch): v1 accepts it ("finds them"). Say so in A's PR.
- Live behaviour of B (a real cut → TV) is unverifiable before the next cut; the server read has a
  test, the office wiring is stub-driven.
