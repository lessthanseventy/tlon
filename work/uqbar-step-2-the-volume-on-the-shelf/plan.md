# Plan — Uqbar step 2: the volume on the shelf

Design: `docs/plans/2026-10-08-uqbar-design.md` §1–2, §7 step 2. Ticket #47. Branch `work/uqbar-step-2-the-volume-on-the-shelf`.

## Already on main (checked)
Step 1 only: agent `uqbar` is registered, off every bench (`server/priv/repo/migrations/20261008150000_uqbar_is_a_citizen.exs`, `Server.Outside`). Nothing of step 2 exists in `office/` (no sprite, no spine, no presence).

## How presence reaches the client (no new API)
`Server.Office.status().roster` already lists every open session (`Server.Staff.roster`: `ended_at` nil), so a live uqbar session is the roster row `agent == "uqbar"`; its `thread_id` is the **focus thread**; `thinking` → working. Assumptions, so they are not silent:
1. "live session" = an open session row (not `warm`: uqbar has no tmux window, so `warm` is always false for it).
2. The `XLVI` lettering is Ink text in the tlon font (tip + label), not pixels on the 8-px-wide sprite, which is too small to hold four letters. The sprite carries a gilt spine stripe.
3. Ribbon colours: idle `ROLE.assistant` (the palette has no indigo), working `ROLE.reviewer` (amber), shipped `ROLE.live`, failing `ROLE.alarm`. Only idle/working are wired now; shipped/failing need step 3's events (YAGNI) but the colour table has all four. State is also in the hit's tip, so colour is never the only signal (WCAG law in `office/AGENTS.md`).
4. The knocked book is stateless: drawn flat while a session is live, upright again when it ends. (The "someone straightens it" pastime is step 6.)

Design: one new kit module `office/kit/uqbar.ts` (sprites, pure book physics, shelf painter). `viewOf` lifts uqbar out of the roster so it can never become a desk, a crew row or a sim actor. `WideRoom` owns one `Book`.

Loop for every task: write the test, run it **red**, implement, run it **green**, `mise run office:check`, commit. Run via `scripts/cap.sh` (see AGENTS.md "Run once, read the log").

---

## Task 1 — pin: the snapshot carries uqbar's session (server)
**File:** `server/test/server/office_test.exs` — add inside `describe "status/0"` (it already has `ws` in setup):
```elixir
    test "an outside citizen's open session is on the roster, with its thread as the focus", %{ws: ws} do
      {:ok, t} = Channel.open_thread(%{title: "a focus", workspace_id: ws.id})
      {:ok, _} = Server.Staff.register_agent(%{name: "uqbar", mandate: "outside", engine: "claude-code"})
      {:ok, _} = Server.Staff.start_session(%{agent_id: Server.Staff.agent_by_name("uqbar").id, thread_id: t.id})

      assert %{thread_id: tid, workspace_id: wsid, thinking: false} = Enum.find(Office.status().roster, &(&1.agent == "uqbar"))
      assert {tid, wsid} == {t.id, ws.id}
      refute Enum.any?(Office.status().bench, &(&1.name == "uqbar"))
    end
```
(If `uqbar` already exists from the migration, `register_agent` may return the existing row or an error; match what `server/test/server/outside_test.exs:17` does and use `Server.Staff.agent_by_name("uqbar")` if it is already there.)
**Done:** `cd server && mix test test/server/office_test.exs` green. Expected green on first run (it pins existing behaviour the client now depends on); if red, fix `Office.roster/3` minimally. Commit: `server: pin that an outside citizen's session reaches the office roster`.

## Task 2 — `viewOf` lifts uqbar out of the roster (office/kit)
**Test first** — new `office/test/uqbar.test.ts`:
```ts
import { describe, expect, test } from "bun:test"
import { crewOf, peopleOf, viewOf } from "../kit/crew"
import { office } from "./golden"

const withUqbar = (thinking = false) => {
  const a = office(3)
  return { ...a, roster: [...a.roster, { agent: "uqbar", thread_id: 101, title: "t1", warm: false, thinking, workspace_id: 1 }] }
}

describe("uqbar in the view", () => {
  test("is lifted out of the roster: no desk, no crew row, no person", () => {
    const v = viewOf(withUqbar(), 1)
    expect(v.uqbar).toMatchObject({ agent: "uqbar", thread_id: 101 })
    expect(v.roster.some((r) => r.agent === "uqbar")).toBe(false)
    expect(crewOf(v).some((c) => c.name === "uqbar")).toBe(false)
    expect(peopleOf(v).some((p) => p.agent === "uqbar")).toBe(false)
  })
  test("is seen from any workspace, and absent without a session", () => {
    expect(viewOf(withUqbar(), 2).uqbar).not.toBeNull()
    expect(viewOf(office(3), 1).uqbar).toBeNull()
  })
})
```
**Code:**
- `office/kit/types.ts`: in `Agents` add `/** uqbar's open session, if any (kit/uqbar.ts): lifted out of the roster by viewOf, so it never gets a desk */ uqbar?: Seat | null` (optional: `EMPTY` unchanged).
- `office/kit/crew.ts` `viewOf`: add `const uqbar = a.roster.find((r) => r.agent === "uqbar") ?? null`; change `sessions` to `a.roster.filter((r) => r.workspace_id === ws && r.agent !== "uqbar")`; add `uqbar,` to the returned object.
**Done:** `cd office && bun test test/uqbar.test.ts` green. Commit: `office: viewOf lifts uqbar out of the roster (no desk, not on the crew board)`.

## Task 3 — the volume: sprites + pure flight (office/kit/uqbar.ts)
**Tests first** — append to `office/test/uqbar.test.ts`:
```ts
import { FRAMES, goalOf, modeOf, moodOf, RIBBON, stepBook, wiggle, type Book } from "../kit/uqbar"
import { ROLE } from "../kit/palette"

describe("the volume", () => {
  test("every frame is rectangular, 12 wide at most, and uses only known paint", () => {
    for (const [name, rows] of Object.entries(FRAMES)) {
      expect(rows.length, name).toBeLessThanOrEqual(8)
      for (const r of rows) { expect(r.length, name).toBe(rows[0]!.length); expect(r, name).toMatch(/^[.rgpkw]+$/) }
    }
    expect(Object.keys(FRAMES).sort()).toEqual(["closed", "flapDown", "flapUp", "open", "riffle"])
  })
  test("the ribbon is a role per state, all different", () => {
    const c = (["idle", "working", "shipped", "failing"] as const).map((m) => RIBBON[m]())
    expect(new Set(c).size).toBe(4)
    expect(RIBBON.working()).toBe(ROLE.reviewer)
  })
  test("mood: mid-turn is working, otherwise idle", () => {
    expect(moodOf({ agent: "uqbar", thread_id: 1, title: "", warm: false, thinking: true })).toBe("working")
    expect(moodOf({ agent: "uqbar", thread_id: 1, title: "", warm: false })).toBe("idle")
  })
  test("a book flies to its goal at speed, riffling on takeoff, and lands exactly", () => {
    const home = { x: 0, y: 0 }, goal = { x: 30, y: 40 }
    let b: Book = { ...home, flying: false, riffle: 0 }
    expect(modeOf(b, home)).toBe("shelved")
    b = stepBook(b, goal)
    expect(b.flying).toBe(true); expect(b.riffle).toBeGreaterThan(0); expect(modeOf(b, home)).toBe("flying")
    for (let i = 0; i < 100 && b.flying; i++) b = stepBook(b, goal)
    expect(b).toEqual({ x: 30, y: 40, flying: false, riffle: 0 })
    expect(modeOf(b, home)).toBe("perched")
    for (let i = 0; i < 100 && (b.flying || modeOf(b, home) !== "shelved"); i++) b = stepBook(b, home)
    expect(modeOf(b, home)).toBe("shelved")
  })
  test("the goal is the focus card, else the board's edge, else home", () => {
    const home = { x: 1, y: 1 }, edge = { x: 9, y: 0 }, cards = new Map([[101, { x: 5, y: 5 }]])
    const seat = (thread_id: number) => ({ agent: "uqbar", thread_id, title: "", warm: false })
    expect(goalOf(null, cards, edge, home)).toEqual(home)
    expect(goalOf(seat(101), cards, edge, home)).toEqual({ x: 5, y: 5 })
    expect(goalOf(seat(999), cards, edge, home)).toEqual(edge)
  })
  test("the spine wiggles now and then, deterministically from the tick", () => {
    expect(wiggle(0)).toBe(0)
    const on = Array.from({ length: 1800 }, (_, t) => wiggle(t)).filter(Boolean).length
    expect(on).toBeGreaterThan(0); expect(on).toBeLessThan(20)
    expect(wiggle(5)).toBe(wiggle(5 + 1800))
  })
})
```
**Code** — new `office/kit/uqbar.ts`:
```ts
// Uqbar, the volume (docs/plans/2026-10-08-uqbar-design.md §1–2): a small flying encyclopedia that is
// the operator's own Claude Code session. It has no desk and is not crew: asleep as one spine too
// many on the lounge shelf, and while a session is live, perched on its focus thread's whiteboard card.
// Sprites are one char per pixel: r cover, g gilt, p page, k ink, w ribbon.
import type { Scene } from "./draw"
import { ROLE, tint } from "./palette"
import type { Seat } from "./types"

export const UQBAR = "uqbar"
export type Mood = "idle" | "working" | "shipped" | "failing"
export type Pt = { x: number; y: number }
/** x, y: top-left of the sprite's body in the room; `riffle`: ticks of page-fan left after takeoff */
export type Book = Pt & { flying: boolean; riffle: number }
export type Mode = "shelved" | "flying" | "perched"

export const FRAMES = {
  closed: ["rrrrrrrr", "rgrrggrr", "rgrrrrrr", "rgrrggrr", "rgrrrrrr", "rrrrrrrr", ".pppppp."],
  open: ["............", "............", "pppppppppppp", "pkpkpkkpkpkp", "pppppppppppp", "rrrrrrrrrrrr", "............", "............"],
  flapUp: ["pp........pp", "ppp......ppp", ".ppp.rr.ppp.", "..pp.rr.pp..", "....grrg....", "....grrg....", "....rrrr....", "............"],
  flapDown: ["............", "....rrrr....", "....grrg....", "..ppgrrgpp..", ".ppp.rr.ppp.", "ppp......ppp", "pp........pp", "............"],
  riffle: ["....pppp....", "..pppppppp..", ".pp.pppp.pp.", "pp..rrrr..pp", "....grrg....", "....grrg....", "....rrrr....", "............"],
} as const
/** the ribbon tail's colour is its state; read at draw time so a theme switch follows */
export const RIBBON: Record<Mood, () => string> = {
  idle: () => ROLE.assistant, working: () => ROLE.reviewer, shipped: () => ROLE.live, failing: () => ROLE.alarm,
}
const oxblood = () => tint(ROLE.alarm, ROLE.ground, 0.6)
const paint = (mood: Mood) => ({ r: oxblood(), g: ROLE.body, p: ROLE.prose, k: ROLE.fieldInk, w: RIBBON[mood]() })

const SPEED = 2, RIFFLE_TICKS = 6
export const moodOf = (s: Seat): Mood => (s.thinking ? "working" : "idle")

/** one tick toward `goal`: straight line, `SPEED` px; the first ticks after takeoff riffle */
export function stepBook(b: Book, goal: Pt): Book {
  const dx = goal.x - b.x, dy = goal.y - b.y, d = Math.hypot(dx, dy)
  if (d <= SPEED) return { x: goal.x, y: goal.y, flying: false, riffle: 0 }
  return { x: b.x + (dx / d) * SPEED, y: b.y + (dy / d) * SPEED, flying: true, riffle: b.flying ? Math.max(0, b.riffle - 1) : RIFFLE_TICKS }
}
export const modeOf = (b: Book, home: Pt): Mode => (b.flying ? "flying" : b.x === home.x && b.y === home.y ? "shelved" : "perched")
/** where the book wants to be: home asleep; else its focus card, else the whiteboard's edge (focus off the board or in another workspace) */
export function goalOf(session: Seat | null | undefined, cards: Map<number, Pt>, edge: Pt, home: Pt): Pt {
  return session ? cards.get(session.thread_id) ?? edge : home
}

/** 1 px nudge for 12 ticks every 180 s of room time (ticks are 100 ms) */
export function wiggle(tick: number): 0 | 1 {
  const t = tick % 1800
  return t < 12 && t % 4 >= 2 ? 1 : 0
}

/** the spine's spot on the shelf, and the book's home: the 10th column of the top row */
export const spineHome = (shelf: { x: number; y: number }): Pt => ({ x: shelf.x + 20, y: shelf.y + 1 })

/**
 * The shelf with its one spine too many (faintly glowing, wiggling now and then) while the book is
 * shelved; the neighbouring spine lying flat while a session is live. Drawn just in front of the shelf.
 */
export function drawShelf(sc: Scene, shelf: { x: number; y: number; w: number; h: number }, shelved: boolean, live: boolean) {
  sc.item(shelf.y + shelf.h + 0.1, () => {
    if (live) { // the 9th spine of the top row (k = 8) knocked flat across the row below it
      sc.px(shelf.x + 18, shelf.y + 2, 1, 5, ROLE.structure)
      sc.px(shelf.x + 14, shelf.y + 6, 5, 1, ROLE.live)
    }
    if (!shelved) return
    const h = spineHome(shelf), x = h.x + wiggle(sc.tick), glow = tint(ROLE.assistant, ROLE.structure, sc.f % 2 ? 0.35 : 0.22)
    sc.px(x - 1, h.y, 1, 6, glow); sc.px(x + 1, h.y, 1, 6, glow); sc.px(x, h.y - 1, 1, 1, glow)
    sc.px(x, h.y, 1, 6, oxblood()); sc.px(x, h.y + 2, 1, 1, ROLE.body)
  })
}

/** the book off the shelf: flying (riffle, then two flap frames) or perched (open at work, else closed), with its label and tip */
export function drawBook(sc: Scene, b: Book, mood: Mood, mode: Mode, on: string) {
  if (mode === "shelved") return
  const frame = mode === "perched" ? (mood === "working" ? FRAMES.open : FRAMES.closed) : b.riffle > 0 ? FRAMES.riffle : (sc.tick >> 1) % 2 ? FRAMES.flapUp : FRAMES.flapDown
  const w = frame[0]!.length, x = Math.round(b.x), y = Math.round(b.y)
  sc.overhead.push(() => {
    sc.blit([...frame], x, y, paint(mood))
    sc.px(x + w, y + 1, 1, 6, RIBBON[mood]()) // the ribbon tail
    sc.text("XLVI", x + w / 2, y - 1, ROLE.body, 9)
    sc.hits.push({ x, y, w: w + 1, h: 8, tip: `Uqbar · Vol. XLVI\n${mood}${on ? ` · ${on}` : ""}` })
  })
}
```
(`Hit` needs an `act`? Check `Hit` in `kit/canvas.ts`/`draw.ts`; if `act` is required, use the card's `{ kind: "thread", tid }` act, else omit — a tip-only hit is fine. `Scene.item`'s base is a number, fractions are allowed.)
**Done:** `cd office && bun test test/uqbar.test.ts` green + `bun run typecheck`. Commit: `office: Uqbar's volume — sprites, flight, the shelf spine, as pure kit code`.

## Task 4 — wire it into the wide room (office/rooms/wide.ts)
**Tests first** — append to `office/test/uqbar.test.ts` (reuse `withUqbar`, `office`; import `WideRoom, corner, zones`, `focus, measure, seeded` from `./golden`, `ROLE, tint` from the kit):
```ts
import { corner, WideRoom, zones } from "../rooms/wide"
import { focus, measure, seeded } from "./golden"
import { spineHome } from "../kit/uqbar"
import { tint } from "../kit/palette"

const WIDTH = 696, NOW = new Date(2026, 9, 5, 21, 0)
const px = (fr: { rgba: Uint8ClampedArray | Uint8Array; width: number }, x: number, y: number) => {
  const i = (y * fr.width + x) * 4
  return "#" + [0, 1, 2].map((k) => fr.rgba[i + k]!.toString(16).padStart(2, "0")).join("").toUpperCase()
}
const shot = (a: ReturnType<typeof withUqbar>, ticks: number) => seeded(3, () => {
  const room = new WideRoom(WIDTH), v = viewOf(a, 1)
  for (let i = 0; i < ticks; i++) room.step(v)
  return room.render(v, focus, measure, NOW)
})
const spot = () => { const s = corner(zones(WIDTH)).shelf, h = spineHome(s); return { s, h } }

describe("uqbar in the wide room", () => {
  test("no session: one extra spine on the shelf, no book anywhere else", () => {
    const fr = shot(office(3) as never, 300), { h } = spot()
    expect(px(fr, h.x, h.y + 3)).toBe(tint(ROLE.alarm, ROLE.ground, 0.6).toUpperCase())
    expect(fr.hits.some((x) => x.tip?.startsWith("Uqbar"))).toBe(false)
  })
  test("a live session: the spine is gone and the book perches on its focus card", () => {
    const fr = shot(withUqbar(true), 600), { h } = spot()
    expect(px(fr, h.x, h.y + 3)).not.toBe(tint(ROLE.alarm, ROLE.ground, 0.6).toUpperCase())
    const book = fr.hits.find((x) => x.tip?.startsWith("Uqbar"))!
    const card = fr.hits.find((x) => x.tip?.startsWith("#101 "))!
    expect(book).toBeDefined(); expect(card).toBeDefined()
    expect(book.y).toBeLessThan(41)                       // on the whiteboard
    expect(book.x).toBeGreaterThanOrEqual(card.x); expect(book.x).toBeLessThanOrEqual(card.x + card.w)
    expect(book.tip).toContain("working")
  })
  test("the session ends: it flies home and the spine is back", () => {
    seeded(3, () => {
      const room = new WideRoom(WIDTH), up = viewOf(withUqbar(), 1), down = viewOf(office(3), 1)
      for (let i = 0; i < 600; i++) room.step(up)
      for (let i = 0; i < 600; i++) room.step(down)
      const fr = room.render(down, focus, measure, NOW), { h } = spot()
      expect(px(fr, h.x, h.y + 3)).toBe(tint(ROLE.alarm, ROLE.ground, 0.6).toUpperCase())
    })
  })
})
```
(Pixel-compare uses the `ROLE` default palette; no `useRoles` in tests. `tint` is lowercase hex; hence `.toUpperCase()` on both sides — keep helper and expectation consistent.)
**Code** in `office/rooms/wide.ts` (read the file around `class WideRoom` first; add imports `drawBook, drawShelf, goalOf, modeOf, moodOf, spineHome, stepBook, type Book, type Pt` from `../kit/uqbar`):
1. Fields beside `private cat`: `private book: Book = { ...spineHome(corner(this.z).shelf), flying: false, riffle: 0 }` (if `this.z` is set in the constructor, initialise there instead), `private cards = new Map<number, Pt>()`, `private boardEdge: Pt = { x: 0, y: 0 }`.
2. In `step(a)`: `this.book = stepBook(this.book, goalOf(a.uqbar, this.cards, this.boardEdge, spineHome(corner(this.z).shelf)))`, and make the returned "changed" flag true while `this.book.flying` (read how `step`'s boolean is used; the TUI redraws on it). The goal comes from the **previous** render's `cards` — one frame late, harmless.
3. In `whiteboard()`: at the top `this.cards.clear(); this.boardEdge = { x: x1 - 24, y: 1 }`; in the `shown.forEach` after `y` is known: `if (it.act.kind === "thread") this.cards.set(it.act.tid, { x: cx + colW - 13, y: y - 8 })` (the book sits on the right end of the card's line).
4. In `render()`, after `this.lounge.draw(...)` / `this.pastimes(...)`: `const home = spineHome(corner(this.z).shelf), mode = modeOf(this.book, home)`; `drawShelf(sc, corner(this.z).shelf, mode === "shelved", !!a.uqbar)`; `if (a.uqbar) drawBook(sc, this.book, moodOf(a.uqbar), mode, `#${a.uqbar.thread_id}`)`. A book still flying home after the session ends (`!a.uqbar`, mode flying) must still draw: use `drawBook(sc, this.book, a.uqbar ? moodOf(a.uqbar) : "idle", mode, a.uqbar ? ... : "")` — i.e. call `drawBook` unconditionally; it returns early when shelved.
5. `office/rooms/rail.ts` is untouched (the rail has no shelf; it never sees `a.uqbar` as a person since `viewOf` stripped it).
**Done:** `cd office && bun test test/uqbar.test.ts test/wide.test.ts` — all three new tests green; `test/wide.test.ts` golden test is now **red** (pixels moved: expected, fixed in Task 5). Also green: walk-through-furniture tests (uqbar adds no blocks). Commit: `office: Uqbar leaves the shelf for its focus card (wide room)`.

## Task 5 — goldens, gate, and seeing it
1. `mise run office:golden` (rewrites `office/test/golden.json`). Review `git diff office/test/golden.json`: the hashes change for every width — expected, since the golden `office(6)` has no uqbar session and now draws the extra spine. Commit: `office: re-hash the wide room's goldens for Uqbar's spine`.
2. `mise run office:check` green (typecheck, whole suite incl. wcag: the book's tip hit and `XLVI` label must not overprint another label — if `test/wcag.test.ts` flags it, nudge the label's y by 1–2 px in `drawBook`, not the test).
3. See it (law: "a frame change is seen, not assumed"): use the `drive-office` skill — run the TUI headless, screenshot the lounge with no uqbar session (one wiggling, glowing spine), then start a session for agent `uqbar` on a thread (`mise run server:claude`-style citizen or `Server.Staff.start_session` from `mise run server:console`) and screenshot again: the book on that thread's card. Attach both to the thread.
**Done:** both screenshots show the ticket's two checks. 

## Task 6 — docs (own commit)
`office/AGENTS.md`: in the `kit/` list add `uqbar.ts` (the volume: sprites, flight, the shelf spine; `viewOf` lifts `uqbar` out of the roster), and in the `rooms/` list a clause on the lounge shelf's extra spine. In `docs/plans/2026-10-08-uqbar-design.md` §7 mark step 2 done only after merge. Commit: `docs: office AGENTS names Uqbar's volume`.

## Out of scope (named, not forgotten)
Shipped/failing ribbon wiring and torn-page aeroplanes (step 3), margin notes (4), the `U` entry (5), the straightening pastime / Nina's swat (6). Hover-at-desk and sit-on-TV perches in design §2 "Working" are step 3's job too (they need act events); step 2 perches on the focus card only.
