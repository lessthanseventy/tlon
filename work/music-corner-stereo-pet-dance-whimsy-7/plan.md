# Plan: stereo marquee + tempo-synced pet dance

Four tasks, each its own commit, each TDD (failing test first). Verify every task with:
`mise run office:check` (= `bun install --frozen-lockfile && bun run typecheck && bun test`, run
from `office/`). All file paths below are relative to `office/`.

**Note on the spec's claim** ("same text-scroll idiom the room already uses elsewhere"): there is
no existing scrolling-text/marquee/ticker code anywhere in `office/` (confirmed by grep for
`marquee|scroll|ticker` — the one `marquee` hit, `rooms/wide.ts:663`, is an arcade cabinet's title
flicker, unrelated). Task 1 below builds the scroll-window helper from scratch, following the
`sc.text`/`fit()` pixel-label conventions already in `kit/draw.ts`/`kit/canvas.ts`. This is new
code, not reuse — flag it as a plan deviation, not a blocker.

---

## Task 1 — `kit/stereo.ts`: parse playerctl output, compute the scroll window

Pure module, no I/O, no Bun.spawnSync. Fully unit-testable.

**Test first** — create `test/stereo.test.ts`:

```ts
import { describe, expect, test } from "bun:test"
import { marqueeWindow, parseNowPlaying } from "../kit/stereo"

describe("parseNowPlaying", () => {
  test("title and artist, no bpm field", () => {
    expect(parseNowPlaying("Song|Artist|")).toEqual({ text: "Song - Artist", bpm: null })
  })
  test("title only, blank artist", () => {
    expect(parseNowPlaying("Song||")).toEqual({ text: "Song", bpm: null })
  })
  test("bpm field present and numeric", () => {
    expect(parseNowPlaying("Song|Artist|128")).toEqual({ text: "Song - Artist", bpm: 128 })
  })
  test("bpm field present but not a number", () => {
    expect(parseNowPlaying("Song|Artist|unknown")).toEqual({ text: "Song - Artist", bpm: null })
  })
  test("no title and no artist: no player playing", () => {
    expect(parseNowPlaying("||")).toBeNull()
    expect(parseNowPlaying("")).toBeNull()
  })
})

describe("marqueeWindow", () => {
  test("text shorter than the window is padded, not scrolled", () => {
    expect(marqueeWindow("hi", 10, 0)).toBe("hi".padEnd(10))
    expect(marqueeWindow("hi", 10, 37)).toBe("hi".padEnd(10))
  })
  test("text longer than the window scrolls as tick advances", () => {
    const text = "a very long now-playing string indeed"
    const a = marqueeWindow(text, 10, 0), b = marqueeWindow(text, 10, 5)
    expect(a.length).toBe(10)
    expect(b.length).toBe(10)
    expect(a).not.toBe(b)
  })
  test("the window wraps around (loops) rather than stopping", () => {
    const text = "loop me"
    const windows = new Set<string>()
    for (let tick = 0; tick < 200; tick++) windows.add(marqueeWindow(text, 6, tick))
    // a short cycle: the same handful of windows repeat, it never grows unbounded
    expect(windows.size).toBeLessThan(20)
  })
})
```

Run it (should fail — module doesn't exist yet): `bun test test/stereo.test.ts`

**Then create `kit/stereo.ts`:**

```ts
// The stereo: what playerctl reports, parsed into a label and an optional tempo; and the
// scroll-window math for a marquee longer than its display width.

/** what's playing, as the stereo's label draws it; `bpm` is null unless a player's metadata
 *  actually carries a tempo field (most don't — the dance trigger stays inert until one does) */
export type NowPlaying = { text: string; bpm: number | null }

/** `stdout` of `playerctl metadata --format '{{ title }}|{{ artist }}|{{ bpm }}'`; null when
 *  there's nothing playing (blank title and artist) */
export function parseNowPlaying(stdout: string): NowPlaying | null {
  const [title = "", artist = "", bpmRaw = ""] = stdout.trim().split("|")
  if (!title && !artist) return null
  const bpm = Number(bpmRaw)
  return { text: artist ? `${title} - ${artist}` : title, bpm: Number.isFinite(bpm) && bpm > 0 ? bpm : null }
}

/** a `width`-wide slice of `text` at `tick`: padded still if it fits, else scrolling, looping
 *  with a gap so the end doesn't run straight into the start */
export function marqueeWindow(text: string, width: number, tick: number): string {
  if (text.length <= width) return text.padEnd(width)
  const loop = text + "   ", doubled = loop + loop
  return doubled.slice(tick % loop.length, (tick % loop.length) + width)
}
```

**Done when:** `bun test test/stereo.test.ts` is green.

---

## Task 2 — `WideRoom`: hold player state, draw the stereo

Depends on Task 1 (`kit/stereo.ts`). Adds a `setPlayer` method (mirroring the existing `channel()`
method for the TV, `rooms/wide.ts:396`) and a private `stereo(sc, x0)` draw method (mirroring the
existing `private tv(sc, x0)`, `rooms/wide.ts:915-920`).

**Test first** — add to `test/wide.test.ts` (same file, same `office()`/`focus`/`measure` helpers
already defined there):

```ts
describe("the stereo", () => {
  test("idle with no player: hit exists, tip says idle, no track text", () => {
    const room = new WideRoom(640), a = viewOf(office(3), 1)
    for (let i = 0; i < 10; i++) room.step(a)
    const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
    const hit = fr.hits.find((h) => h.tip.startsWith("the stereo"))
    expect(hit).toBeTruthy()
    expect(hit!.tip).toContain("idle")
  })

  test("a player set: the tip names the track", () => {
    const room = new WideRoom(640), a = viewOf(office(3), 1)
    room.setPlayer({ text: "Test Song - Test Artist", bpm: null })
    for (let i = 0; i < 10; i++) room.step(a)
    const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
    const hit = fr.hits.find((h) => h.tip.startsWith("the stereo"))
    expect(hit!.tip).toContain("Test Song - Test Artist")
  })

  test("clearing the player goes back to idle", () => {
    const room = new WideRoom(640), a = viewOf(office(3), 1)
    room.setPlayer({ text: "Test Song", bpm: null })
    room.setPlayer(null)
    for (let i = 0; i < 10; i++) room.step(a)
    const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
    expect(fr.hits.find((h) => h.tip.startsWith("the stereo"))!.tip).toContain("idle")
  })
})
```

Run it (fails — no `setPlayer`, no stereo hit yet): `bun test test/wide.test.ts`

**Then implement in `rooms/wide.ts`:**

1. Import the new module — add to the import block near the top (after the `Tv` import at line 13):
   ```ts
   import { marqueeWindow, parseNowPlaying, type NowPlaying } from "../kit/stereo"
   ```
   (`parseNowPlaying` isn't used in this file yet — Task 3 uses it in `tui/main.ts`; only
   `marqueeWindow` and the `NowPlaying` type are needed here. Import just those two:)
   ```ts
   import { marqueeWindow, type NowPlaying } from "../kit/stereo"
   ```

2. Add a field next to `tvSet` (line 253):
   ```ts
   private readonly tvSet = new Tv(48, 28)
   private player: NowPlaying | null = null
   ```

3. Add a public setter next to `channel()` (line 396):
   ```ts
   channel() { this.tvSet.next() }
   /** the TUI calls this every ~2s with whatever playerctl reports (or null — no player running) */
   setPlayer(p: NowPlaying | null) { this.player = p }
   ```

4. Add the draw method next to `private tv(sc, x0)` (after line 920):
   ```ts
   /** the stereo: whatever's playing scrolls across its label; idle and silent with no player */
   private stereo(sc: Scene, x0: number) {
     const w = 44, labelW = 20
     sc.px(x0, 6, w, 20, ROLE.inactive); sc.px(x0 + 2, 8, w - 4, 6, ROLE.ground)
     const label = this.player ? marqueeWindow(this.player.text, labelW, sc.tick) : "no signal".padEnd(labelW)
     sc.text(label, x0 + 3, 12, this.player ? ROLE.fieldInk : ROLE.inactive, 7)
     sc.px(x0 + 2, 16, w - 4, 8, ROLE.edge)
     for (let i = 0; i < 3; i++) sc.px(x0 + 6 + i * 12, 18, 6, 4, ROLE.structure)
     sc.hits.push({
       x: x0, y: 6, w, h: 20,
       tip: this.player ? `the stereo: ${this.player.text}` : "the stereo: idle — no signal",
       act: { kind: "stereo" },
     })
   }
   ```

5. Wire it into the back-wall sequence (`rooms/wide.ts:429`, next to `this.tv(...)`):
   ```ts
   this.tv(sc, L0 + 36)
   this.stereo(sc, L0 + 96)
   this.clock(sc, W - 24, now)
   ```
   `L0 + 96` is a starting guess (clear of the TV's `L0+36..L0+88` span); if it overlaps the clock
   at this room's narrower widths, nudge the offset — confirm visually with `drive-office` (Task 4
   covers wiring the real poll; until then, call `room.setPlayer(...)` by hand in a throwaway test
   or via the TUI's dev console to check placement). This offset is explicitly the implementer's
   call per spec, not a design decision to get permission for.

**Done when:** `bun test test/wide.test.ts` is green and `bun run typecheck` passes.

---

## Task 3 — `tui/main.ts`: poll playerctl, feed the room

Depends on Task 1 (`kit/stereo.ts`) and Task 2 (`WideRoom.setPlayer`). No test — this is an I/O
shellout wired into the TUI's existing interval loop; the spec explicitly says no
`office:check` assertion is expected to cover the playerctl integration itself. Verify by running
and by `drive-office` (Task 4's manual check covers this end to end).

**Implement in `tui/main.ts`:**

1. Add the import (near other `kit/` imports at the top):
   ```ts
   import { parseNowPlaying } from "../kit/stereo"
   ```

2. Add a poll function, mirroring the `tmux = (...a) => Bun.spawnSync(["tmux", "-L", OWN_TMUX, ...a])`
   helper pattern at `tui/main.ts:1135` and the exit-code check at `tui/main.ts:409-411`. Place it
   near `peekScreen` (around line 404):
   ```ts
   /** playerctl, polled every ~2s: feeds the wide room's stereo marquee + dance trigger */
   function pollPlayer() {
     const rm = room()
     if (!(rm instanceof WideRoom)) return
     const r = Bun.spawnSync(["playerctl", "metadata", "--format", "{{ title }}|{{ artist }}|{{ bpm }}"])
     rm.setPlayer(r.exitCode === 0 ? parseNowPlaying(r.stdout.toString()) : null)
   }
   ```
   (`WideRoom` must already be imported in this file for the existing `case "tv"` instanceof check
   at line 236 — reuse that import, don't add a second one.)

3. Register the interval alongside the others in `main()` (`tui/main.ts:1244`, right after
   `setInterval(refresh, 10_000)`):
   ```ts
   setInterval(refresh, 10_000)
   setInterval(pollPlayer, 2000)
   ```

**Done when:** `bun run typecheck` passes, and running `mise run office:run` with a local
`playerctl` (any MPRIS player, e.g. a browser tab playing audio) shows the stereo's label update
within ~2s; with no player running, the stereo shows "no signal" and nothing throws.

---

## Task 4 — tempo-synced dance for Nina and Argos

Depends on Task 2 (`this.player` on `WideRoom`). No new `CatMode`/`Dog.mode` value — dance is a
draw-time overlay on the existing `walk`/`sit` frames (per spec: "cycling its existing walk/sit
frames", not a new state), gated the same way `grooming` already is in `drawCat`.

**Test first** — add to `test/pets.test.ts` (reuse its existing `chance()` helper and the
`room as unknown as Pets` cast pattern already used there for reaching `cat`/`dog`/`tick`):

```ts
describe("tempo-synced dance", () => {
  test("bpm > 120, cat awake and not fussed/zooming: dancing reads true", () => {
    const room = new WideRoom(640) as unknown as Pets & { setPlayer(p: unknown): void }
    room.setPlayer({ text: "x", bpm: 140 })
    room.cat.mode = "sit"; room.cat.fuss = null
    expect(dancing(room.cat.mode, room.cat.fuss, 140)).toBe(true)
  })
  test("bpm <= 120: never dances", () => {
    expect(dancing("sit", null, 120)).toBe(false)
  })
  test("no bpm: never dances", () => {
    expect(dancing("sit", null, null)).toBe(false)
  })
  test("asleep: never dances even with a fast bpm", () => {
    expect(dancing("sleep", null, 140)).toBe(false)
  })
  test("mid-zoomies: never dances", () => {
    expect(dancing("zoom", null, 140)).toBe(false)
  })
  test("fussed: never dances", () => {
    expect(dancing("sit", { kind: "pat", from: { x: 0, y: 0 }, until: 999 }, 140)).toBe(false)
  })
})
```

This names a `dancing()` helper that doesn't exist yet — run it to confirm the failure
(`bun test test/pets.test.ts`), then implement:

**In `kit/draw.ts`:**

1. Export a small pure predicate (place it above `drawCat`, near its other helpers):
   ```ts
   /** bpm present and fast, and the pet isn't asleep, fussed, or mid-zoomies */
   export function dancing(mode: string, fuss: Fussing | null, bpm: number | null): boolean {
     return bpm !== null && bpm > 120 && mode !== "sleep" && mode !== "zoom" && !fuss
   }
   ```

2. Change `drawCat`'s signature (line 156) to take the stereo's bpm:
   ```ts
   export function drawCat(sc: Scene, c: Cat, over: number | null, bpm: number | null) {
   ```

3. Inside, right after `const grooming = ...` (line 158), compute the dance beat and use it for
   both the flip and the bob — tying them to the same tempo-synced phase, toggling twice per beat
   (`600 / bpm` ticks per beat at 10 ticks/second, so `300 / bpm` ticks per half-beat):
   ```ts
   const dance = dancing(c.mode, c.fuss, bpm)
   const phase = dance ? Math.floor((sc.tick * bpm!) / 300) % 2 : 0
   ```

4. Use `phase` in place of `c.face`'s sign for the flip, and add it as a bob offset. Change:
   ```ts
   const rows = c.face < 0 ? rows0.map((r) => [...r].reverse().join("")) : rows0
   const w = rows[0]!.length, h = rows.length, x = c.x - Math.floor(w / 2), y = c.y - h
   ```
   to:
   ```ts
   const flipped = dance ? phase === 1 : c.face < 0
   const rows = flipped ? rows0.map((r) => [...r].reverse().join("")) : rows0
   const w = rows[0]!.length, h = rows.length, x = c.x - Math.floor(w / 2), y = c.y - h - (dance ? phase : 0)
   ```

**In `rooms/wide.ts`:**

5. Pass the bpm through at the call site (line 498):
   ```ts
   drawCat(sc, c, (c.x === CAT_DESK.x || c.x === PERCH_TOP.x) && c.y < 100 ? 104 : c.x === chair && c.y === 82 ? 84 : c.x === CAT_WARM.x && c.y === CAT_WARM.y ? RADIATOR.y + RADIATOR.h + 1 : null, this.player?.bpm ?? null)
   ```

6. `drawDog` is private to `WideRoom` itself (line 593, not in `kit/draw.ts`), so it already has
   `this.player` in scope — no new parameter needed. Inside `private drawDog(sc: Scene)`, after
   `const belly = sc.tick < d.belly` (around line 597), add:
   ```ts
   const bpm = this.player?.bpm ?? null
   const dance = dancing(d.mode, d.fuss, bpm)
   const phase = dance ? Math.floor((sc.tick * bpm!) / 300) % 2 : 0
   ```
   and change the existing flip/position lines:
   ```ts
   const rows = d.face < 0 ? rows0.map((r) => [...r].reverse().join("")) : rows0
   const w = rows[0]!.length, h = rows.length, x = d.x - Math.floor(w / 2), y = d.y - h
   ```
   to:
   ```ts
   const flipped = dance ? phase === 1 : d.face < 0
   const rows = flipped ? rows0.map((r) => [...r].reverse().join("")) : rows0
   const w = rows[0]!.length, h = rows.length, x = d.x - Math.floor(w / 2), y = d.y - h - (dance ? phase : 0)
   ```
   and import `dancing` alongside the other `kit/draw` imports at the top of `rooms/wide.ts`
   (line 9): `import { dancing, drawActors, drawCat, drawFuss, drawParty, Scene, type Focus } from "../kit/draw"`.

**Done when:** `bun test test/pets.test.ts` is green, `bun run typecheck` passes, and — per the
spec's own exit criteria — a manual `drive-office` check with a player set to a bpm > 120 via
`setPlayer` shows Nina and/or Argos bob+flip while dancing, and drop out of it the moment bpm
drops or the mode machine forces sleep/fuss/zoom.

---

## Order and final gate

Commit each task separately, in order (2 depends on 1; 3 depends on 1+2; 4 depends on 2).
After all four: `mise run office:check` green, then the manual `drive-office` walkthrough from the
spec's "Exit / verification" section (idle-with-no-player, marquee-with-a-player, dance-with-bpm).
One PR for the whole stack, per the ticket's scope.
