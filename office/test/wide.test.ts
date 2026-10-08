import { describe, expect, test } from "bun:test"
import { crewOf, viewOf } from "../kit/crew"
import type { Spot } from "../kit/sim"
import { catCornerTile } from "../kit/tiles/cat-corner"
import { gamesTile } from "../kit/tiles/games"
import { kitchenTile } from "../kit/tiles/kitchen"
import { loungeTile } from "../kit/tiles/lounge"
import { meetingTile } from "../kit/tiles/meeting"
import { officeTile } from "../kit/tiles/office"
import type { Home } from "../kit/home"
import { annexHeight } from "../kit/homeart"
import { type Agents, EMPTY } from "../kit/types"
import type { Tv } from "../kit/tv"
import { WIDE_H, WideRoom, widePlan, zones } from "../rooms/wide"
import { focus, frameHashes, GOLDEN, measure, office, seeded } from "./golden"

describe("the wide room", () => {
  for (const w of [540, 560, 640]) {
    test(`renders a full frame ${w} wide`, () => {
      const room = new WideRoom(w), a = viewOf(office(3), 1)
      for (let i = 0; i < 300; i++) room.step(a)
      const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
      expect([fr.width, fr.height]).toEqual([w, WIDE_H])
      for (let i = 3; i < fr.rgba.length; i += 4) expect(fr.rgba[i]).toBe(255)
      for (const h of fr.hits) { expect(h.x).toBeGreaterThanOrEqual(-1); expect(h.x + h.w).toBeLessThanOrEqual(w + 1) }
    })
  }

  test("a home hangs below the office as an annex; the office rows stay put", () => {
    const home: Home = { tiles: [{ kind: "garden", at: [0, 0] }] }
    const a = viewOf(office(3), 1), now = new Date(2026, 9, 5, 21, 0)
    const shot = (h?: Home) => seeded(7, () => {
      const room = new WideRoom(696)
      if (h) room.setHome(h)
      for (let i = 0; i < 50; i++) room.step(a)
      return room.render(a, focus, measure, now)
    })
    const bare = shot(), withHome = shot(home)
    expect(bare.height).toBe(WIDE_H)
    expect(withHome.height).toBe(WIDE_H + annexHeight(home))
    expect(Buffer.from(withHome.rgba.slice(0, bare.rgba.length)).equals(Buffer.from(bare.rgba))).toBe(true)
  })

  test("the room's pixels don't move: a golden hash per width", async () => {
    const golden: Record<string, string> = await Bun.file(GOLDEN).json()
    const got = frameHashes()
    const moved = Object.keys(golden).filter((w) => got[w] !== golden[w])
    expect(moved.length ? `widths ${moved.join(", ")} moved; if that is meant, re-hash: mise run office:golden` : "").toBe("")
    expect(Object.keys(got)).toEqual(Object.keys(golden))
  })

  test("the in-tray, the beacon and the rack say what they hold, and open their cards", () => {
    const tips = (a: Agents, tray: number) => new Map(new WideRoom(560).render(a, { ...focus, tray }, measure).hits.map((h) => [h.act.kind, h.tip]))
    const quiet = tips(viewOf({ ...office(1), triage: { "1": 0 }, health: { state: "ok", problems: [] } }, 1), 0)
    expect([quiet.get("tray"), quiet.get("beacon"), quiet.get("rack")]).toEqual(["the in-tray: what just happened", "the beacon: nothing is stuck", "the server rack: all green"])
    const busy = tips(viewOf({ ...office(1), triage: { "1": 3, "2": 9 }, health: { state: "warn", problems: ["disk 95% full"] } }, 1), 4)
    expect(busy.get("tray")).toContain("4 new")
    // the beacon counts this workspace's stuck things, never another's
    expect(busy.get("beacon")).toContain("3 issues")
    expect(busy.get("beacon")).toContain("nothing for you to do")
    expect(busy.get("rack")).toContain("disk 95% full")
  })

  test("mid-turn works at a desk; warm but unbusy waits there too; cold goes to the lounge", () => seeded(3, () => {
    const a0 = office(2)
    const state = (i: number) => (i === 1 ? { warm: true, thinking: true } : i === 2 ? { warm: true, thinking: false } : { warm: false, thinking: false })
    const a = viewOf({ ...a0, roster: a0.roster.map((r, i) => ({ ...r, ...state(i) })) }, 1)
    const room = new WideRoom(560)
    for (let i = 0; i < 600; i++) room.step(a)
    const at = (name: string) => (room as unknown as { actors: Map<string, { spot: { kind: string } }> }).actors.get(name)!.spot.kind
    expect([at("hronir"), at("w0")]).toEqual(["desk", "desk"])
    expect(["couch", "cooler", "coffee", "roam"]).toContain(at("w1"))
    expect(crewOf(a).map((c) => [c.name, c.status])).toEqual([["tertius", "idle"], ["hronir", "working"], ["w0", "idle"], ["w1", "idle"]])
  }))

  test("the pets do what you tell them: Nina naps, zooms, comes to your desk; Argos goes to bed", () => seeded(5, () => {
    const room = new WideRoom(560), a = viewOf(office(1), 1)
    const pets = room as unknown as { cat: { x: number; y: number; mode: string; path: unknown[] }; dog: { x: number; y: number; mode: string; path: unknown[] } }
    const settle = (done: () => boolean) => { for (let i = 0; i < 3_000 && !done(); i++) room.step(a) }

    room.catDo("come")
    settle(() => !pets.cat.path.length)
    expect([pets.cat.x, pets.cat.y]).toEqual([37, 75])
    expect(room.catDo("zoomies")).toBe(true)
    expect(pets.cat.mode).toBe("zoom")

    room.dogDo("bed")
    settle(() => !pets.dog.path.length)
    expect(pets.dog.mode).toBe("sleep")
  }))

  test("send a pet to cheer someone on: over they go, and say something to them by name", () => seeded(7, () => {
    const a0 = office(0)
    const a = viewOf({ ...a0, roster: a0.roster.map((r) => (r.agent === "hronir" ? { ...r, warm: true, thinking: true } : r)) }, 1)
    const room = new WideRoom(560)
    for (let i = 0; i < 600; i++) room.step(a)
    const pets = room as unknown as { cat: { path: unknown[]; said: string | null }; dog: { path: unknown[]; said: string | null } }
    const hronir = () => (room as unknown as { actors: Map<string, { emote: string | null }> }).actors.get("hronir")!
    const settle = (done: () => boolean) => { for (let i = 0; i < 3_000 && !done(); i++) room.step(a) }

    expect(room.catCheer("hronir")).toBe(true)
    settle(() => !pets.cat.path.length)
    expect(pets.cat.said).toContain("hronir")
    expect(hronir().emote).toBe("♥")

    expect(room.dogCheer("hronir")).toBe(true)
    settle(() => !pets.dog.path.length)
    expect(pets.dog.said).toContain("hronir")
    expect(room.catCheer("nobody-here")).toBe(false)
  }))

  test("easter eggs in the room: the cat on the keyboard, the howl, the disco, the night owls", () => seeded(11, () => {
    const a0 = office(0)
    const a = viewOf({ ...a0, roster: a0.roster.map((r) => (r.agent === "hronir" ? { ...r, warm: true, thinking: true } : r)) }, 1)
    const room = new WideRoom(560)
    for (let i = 0; i < 600; i++) room.step(a)
    const r = room as unknown as {
      cat: { path: unknown[]; said: string | null }
      dog: { path: unknown[]; said: string | null }
      talk: Map<string, { text: string | null }>
      actors: Map<string, { emote: string | null }>
      ship(actor: unknown): void
      hour: () => number
    }
    const settle = (done: () => boolean) => { for (let i = 0; i < 3_000 && !done(); i++) room.step(a) }

    // Nina takes the keyboard: hronir's next words are hers
    expect(room.catKeyboard("hronir")).toBe(true)
    settle(() => !r.cat.path.length)
    expect(r.talk.get("hronir")?.text).toMatch(/^[a-z;',.\/\[\]]{8,}$/)

    // someone ships: Argos howls, and is off on a lap of honour
    r.ship(r.actors.get("hronir"))
    expect(r.dog.said).toMatch(/AWO+/)
    expect(r.dog.path.length).toBeGreaterThan(0)

    // the Konami code: everyone gets a heart, and the room has a beat for the pets to dance to
    room.disco()
    expect([...r.actors.values()].every((x) => x.emote === "♥")).toBe(true)
    expect(room.bpm()).toBeGreaterThan(120)

    // a level-up in the snapshot throws the party; the first snapshot is only a baseline
    const lv = (level: number): Agents => ({ ...EMPTY, ok: true, life: { "7": { level, xp: 0, due: [] } } })
    const lvRoom = new WideRoom(560)
    lvRoom.step(lv(3))
    expect(lvRoom.bpm()).toBeNull()
    lvRoom.step(lv(4))
    expect(lvRoom.bpm()).toBeGreaterThan(120)
    expect((lvRoom as unknown as { tvSet: Tv }).tvSet.channel).toBe("level")

    // the small hours: someone at their desk yawns
    r.hour = () => 2
    for (const x of r.actors.values()) x.emote = null
    let yawned = false
    for (let i = 0; i < 4_000 && !yawned; i++) { room.step(a); yawned = [...r.actors.values()].some((x) => x.emote === "z") }
    expect(yawned).toBe(true)
  }))

  test("a thread waiting on you is brought to you by its lead alone — the rest of its people get on", () => seeded(13, () => {
    const a0 = office(1)
    // hronir leads #900, at its gate; w0 has a seat on it too
    const a = viewOf({
      ...a0,
      threads: [...a0.threads, { id: 900, title: "at the gate", stage: "review", awaiting: "andrew", workspace_id: 1, lead: "hronir" }],
      roster: [...a0.roster, { agent: "hronir", thread_id: 900, title: "at the gate", warm: true, thinking: false, workspace_id: 1 }, { agent: "w0", thread_id: 900, title: "at the gate", warm: true, thinking: false, workspace_id: 1 }],
    }, 1)
    expect(crewOf(a).filter((c) => c.status === "waiting").map((c) => c.name)).toEqual(["hronir"])

    const room = new WideRoom(560)
    for (let i = 0; i < 1_500; i++) room.step(a)
    const queued = [...(room as unknown as { actors: Map<string, { spot: { kind: string } }> }).actors].filter(([, x]) => x.spot.kind === "queue").map(([k]) => k)
    expect(queued).toEqual(["hronir"])
  }))

  test("a pet never says the same thing twice in a row", () => seeded(9, () => {
    const room = new WideRoom(560)
    const said = (room as unknown as { cat: { said: string | null } }).cat
    const lines: string[] = []
    for (let i = 0; i < 40; i++) { room.pet(); lines.push(said.said!) }
    for (let i = 1; i < lines.length; i++) expect(lines[i]).not.toBe(lines[i - 1])
    expect(new Set(lines.slice(0, 4)).size).toBe(4)
  }))

  test("the wall calendar counts the days still to come with something scheduled", () => {
    const tip = (calendar: Record<string, number[]>) => new WideRoom(560).render(viewOf({ ...office(1), calendar }, 1), focus, measure, new Date(2026, 9, 10, 12, 0)).hits.find((h) => h.act.kind === "calendar")!.tip
    expect(tip({ "1": [2, 9, 16, 23, 30], "2": [11, 12] })).toContain("something scheduled on 3 day(s) still to come")
    expect(tip({})).not.toContain("scheduled")
  })

  test("at night every lamp is registered before the glow is painted: lounge, manager and lead desks", () => {
    const room = new WideRoom(560), a = viewOf(office(3), 1), seen: number[] = []
    const r = room as unknown as { nightfall: (sc: { lamps: unknown[] }, now: Date) => void }
    const real = r.nightfall.bind(room)
    r.nightfall = (sc, now) => { seen.push(sc.lamps.length); real(sc, now) }
    for (let i = 0; i < 300; i++) room.step(a)
    room.render(a, focus, measure, new Date(2026, 9, 5, 3, 0))
    expect(seen).toEqual([3])
  })

  test("a full office of ten seats everyone, each at their own place", () => {
    const room = new WideRoom(560), a = viewOf(office(8), 1)
    for (let i = 0; i < 400; i++) room.step(a)
    const seated = room.render(a, focus, measure).hits.filter((h) => h.act.kind === "person" && h.tip.includes("at the desk"))
    expect(seated.length).toBe(10)
    expect(new Set(seated.map((h) => `${h.x},${h.y}`)).size).toBe(10)
  })

  // 9000 ticks of the room: ~1.5 s alone, ten times that under the whole gate's load
  test("Argos keeps off the furniture, and gets around", () => seeded(13, () => {
    for (const w of [540, 696, 900]) {
      const room = new WideRoom(w), a = viewOf(office(6), 1), plan = widePlan(w), blocks = plan.blocks(plan.layout(a))
      const seen = new Set<string>()
      for (let i = 0; i < 3000; i++) {
        room.step(a)
        const d = (room as unknown as { dog: { x: number; y: number } }).dog
        const hit = blocks.find((b) => d.x > b.x && d.x < b.x + b.w - 1 && d.y > b.y && d.y < b.y + b.h - 1)
        if (hit) throw new Error(`Argos at ${d.x},${d.y} (w ${w}, tick ${i}) is inside ${JSON.stringify(hit)}`)
        seen.add(`${Math.round(d.x / 40)},${Math.round(d.y / 40)}`)
      }
      expect(seen.size).toBeGreaterThan(3)
    }
  }), 30_000)

  // up to 400k ticks of the room: seconds of CPU, more when the gate runs every suite at once
  test("Nina and Argos get up to things, and Argos still keeps off the furniture doing it", () => seeded(7, () => {
    const room = new WideRoom(696), a = viewOf(office(6), 1), plan = widePlan(696), blocks = plan.blocks(plan.layout(a))
    // by day: after dark the pets are in bed
    ;(room as unknown as { hour: () => number }).hour = () => 16
    const kinds = new Set<string>()
    for (let i = 0; i < 400_000 && kinds.size < 2; i++) {
      room.step(a)
      const r = room as unknown as { dog: { x: number; y: number }; antic: { kind: string } | null }
      if (r.antic) kinds.add(r.antic.kind)
      const hit = blocks.find((b) => r.dog.x > b.x && r.dog.x < b.x + b.w - 1 && r.dog.y > b.y && r.dog.y < b.y + b.h - 1)
      if (hit) throw new Error(`Argos at ${r.dog.x},${r.dog.y} (tick ${i}, ${r.antic?.kind ?? "no antic"}) is inside ${JSON.stringify(hit)}`)
    }
    expect(kinds.size).toBeGreaterThanOrEqual(2)
  }), 30_000)

  // up to 400k ticks of the room: seconds of CPU, more when the gate runs every suite at once
  test("Nina gets the zoomies: tears between the room's leaps, then lands on its floor and sits", () => seeded(11, () => {
    const room = new WideRoom(696), a = viewOf(office(6), 1)
    // by day: after dark the pets are in bed
    ;(room as unknown as { hour: () => number }).hour = () => 16
    const c = (room as unknown as { cat: { x: number; y: number; mode: string; leaps: { x: number; y: number }[] } }).cat
    const visited = new Set<string>()
    let runs = 0, was = c.mode
    for (let i = 0; i < 400_000 && runs < 3; i++) {
      room.step(a)
      if (c.mode === "zoom" && c.leaps.some((q) => q.x === c.x && q.y === c.y)) visited.add(`${c.x},${c.y}`)
      if (was === "zoom" && c.mode !== "zoom") {
        runs++
        expect({ mode: c.mode, at: [c.x, c.y] }).toEqual({ mode: "sit", at: [c.leaps[0]!.x, c.leaps[0]!.y] })
      }
      was = c.mode
    }
    expect(runs).toBe(3)
    expect(visited.size).toBeGreaterThanOrEqual(3)
  }), 30_000)

  // every route between every fixed spot, at three widths: seconds of CPU, more under a full gate
  test("no walk crosses the furniture", () => {
    for (const w of [540, 560, 700]) {
      const plan = widePlan(w), l = plan.layout(viewOf(office(8), 1))
      const homes = l.people.map((p) => plan.home(l, p.agent)).filter((s): s is Spot => !!s)
      const spots = [...homes, ...plan.queue, ...plan.lounge, plan.exit, plan.pen, plan.roam(l)]
      const blocks = plan.blocks(l)
      const inside = (x: number, y: number) => blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
      for (const from of spots) for (const to of spots) {
        const start = from.aisle
        const path = plan.route(from.x, start, to)
        // the first and last legs sit down and stand up; everything between is walking
        let x = path[0]!.x, y = path[0]!.y
        for (const p of path.slice(1, -1)) {
          while (x !== p.x || y !== p.y) {
            if (x !== p.x) x += Math.sign(p.x - x); else y += Math.sign(p.y - y)
            const hit = inside(x, y)
            if (hit) throw new Error(`${from.kind}@${from.x},${from.y} → ${to.kind}@${to.x},${to.y} (w ${w}) walks through ${JSON.stringify(hit)} at ${x},${y}`)
          }
        }
      }
    }
  }, 30_000)

  test("no walk crosses the furniture, tile by tile", () => {
    for (const w of [540, 560, 700]) {
      const z = zones(w), plan = widePlan(w), l = plan.layout(viewOf(office(8), 1))
      const tiles = [gamesTile(z), kitchenTile(z, w), meetingTile(z), loungeTile(z), catCornerTile(z), officeTile(z)]
      for (const tile of tiles) {
        const blocks = tile.blocks(l), spots = Object.values(tile.spots(l)).flat()
        const inside = (x: number, y: number) => blocks.find((b) => x > b.x && x < b.x + b.w - 1 && y > b.y && y < b.y + b.h - 1)
        for (const s of spots) if (inside(s.x, s.y)) throw new Error(`${tile.kind}@${w}: spot ${s.kind}@${s.x},${s.y} is inside its own block`)
      }
    }
  })
})

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
