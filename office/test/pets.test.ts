import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { dancing } from "../kit/draw"
import { ARGOS, cycleAxis, DEFAULT_PETS, dots, previewOf, resolvePets, TEMPERAMENTS } from "../kit/pets"
import { NINA, SWEET } from "../kit/voices"
import { CAT, DOG } from "../kit/sprites"
import { EMPTY, type Agents } from "../kit/types"
import { WideRoom } from "../rooms/wide"

const focus = { picked: null, armed: null, person: null }
const measure = (s: string) => s.length * 2

/** run `f` with Math.random fixed at `r`: every chance taken (0), or none (0.999) */
function chance<T>(r: number, f: () => T): T {
  const real = Math.random
  Math.random = () => r
  try { return f() } finally { Math.random = real }
}

function office(state: { thinking: boolean; doing?: string | null }): Agents {
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "builder", meta: false, read_only: false, model: "" }],
    bench: [{ workspace_id: 1, seat_id: 1, agent_id: 1, name: "hronir", archetype: "builder", lead: true, model: null, ask: null }],
    threads: [{ id: 100, title: "t", stage: null, awaiting: null, workspace_id: 1, lead: "hronir" }],
    roster: [{ agent: "hronir", thread_id: 100, title: "t", warm: false, workspace_id: 1, ...state }],
  }
}
type Pets = { cat: { x: number; y: number; mode: string; stretch: number; said: string | null; fuss: unknown; path: unknown[] }; dog: { x: number; y: number; fuss: unknown; mode: string; belly: number; said: string | null; path: unknown[] }; tick: number }
const balloons = (room: WideRoom, a: Agents) => room.render(a, focus, measure).ink.filter((i) => i.t === "balloon")

describe("the pets' sprites", () => {
  test("every frame is a rectangle", () => {
    for (const [name, frames] of [...Object.entries(CAT), ...Object.entries(DOG)]) for (const rows of frames) {
      expect({ name, widths: new Set(rows.map((r) => r.length)).size }).toEqual({ name, widths: 1 })
    }
  })
})

describe("the pets talk", () => {
  test("Nina, clicked awake, stretches and says so — in a balloon over her", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
    room.step(a)
    expect(pets.cat.mode).toBe("sleep")
    room.pet()
    expect(pets.cat.stretch).toBeGreaterThan(pets.tick)
    expect(balloons(room, a).some((b) => b.t === "balloon" && b.cx === pets.cat.x)).toBe(true)
  }))

  test("Argos, patted where he lies, rolls over for a belly rub and says so", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
    room.step(a)
    room.patDog()
    expect(pets.dog.belly).toBeGreaterThan(pets.tick)
    expect(balloons(room, a).some((b) => b.t === "balloon" && b.cx === pets.dog.x)).toBe(true)
  }))

  test("someone finishing a turn gets a word from the pets, by name where the line has one", () => {
    const room = new WideRoom(560), pets = room as unknown as Pets
    chance(0.999, () => { for (let i = 0; i < 600; i++) room.step(viewOf(office({ thinking: true }), 1)) })
    chance(0, () => room.step(viewOf(office({ thinking: false }), 1)))
    expect(pets.cat.said).toBeTruthy()
    expect(pets.dog.said).toBeTruthy()
    expect(pets.dog.said).not.toContain("{name}")
  })

  test("someone idling near Nina makes a fuss of her — a pat, a scratch or a treat — and she has views", () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets & { actors: Map<string, { x: number; y: number; spot: { kind: string }; moving: boolean; path: unknown[] }> }
    const idler = () => [...pets.actors.values()][0]!
    chance(0.999, () => { for (let i = 0; i < 3_000 && (i < 600 || idler().moving || idler().path.length); i++) room.step(a) })
    const settled = idler()
    expect(["desk", "queue"]).not.toContain(settled.spot.kind)
    Object.assign(pets.cat, { x: settled.x + 10, y: settled.y, mode: "sit", path: [], purr: 0, stretch: 0 })
    chance(0, () => room.step(a))
    expect(pets.cat.fuss).toMatchObject({ kind: "pat" })
    expect(pets.cat.said).toBeTruthy()
  })

  test("Argos sometimes fetches the newspaper and brings it to your office", () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
    chance(0.999, () => { for (let i = 0; i < 3_000 && (i < 600 || pets.dog.mode === "sleep" || pets.dog.path.length); i++) room.step(a) })
    chance(0, () => room.step(a))
    expect(pets.dog.mode).toBe("walk")
    expect(ARGOS.paper).toContain(pets.dog.said!)
    expect(balloons(room, a).some((b) => b.t === "balloon" && b.cx === pets.dog.x)).toBe(true)
  })

  test("Argos doesn't wander off for the paper mid-fuss", () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
    chance(0.999, () => { for (let i = 0; i < 3_000 && (i < 600 || pets.dog.mode === "sleep" || pets.dog.path.length); i++) room.step(a) })
    pets.dog.fuss = { kind: "pat", from: { x: pets.dog.x, y: pets.dog.y }, until: 1e9 }
    chance(0, () => room.step(a))
    expect(ARGOS.paper).not.toContain(pets.dog.said!)
  })

  test("the server's lines come first, none said twice while another is unsaid, the coworker named", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
    room.hear({ Nina: { pet: ["Adore me, {name}.", "Kneel."] } })
    room.step(a)
    room.pet()
    const first = pets.cat.said
    room.pet()
    expect(new Set([first, pets.cat.said])).toEqual(new Set(["Adore me, you.", "Kneel."]))
  }))
})

describe("tempo-synced dance", () => {
  test("bpm > 120, cat awake and not fussed/zooming: dancing reads true", () => {
    const room = new WideRoom(640) as unknown as Pets & { setPlayer(p: unknown): void }
    room.setPlayer({ text: "x", bpm: 140 })
    room.cat.mode = "sit"; room.cat.fuss = null
    expect(dancing(room.cat.mode, room.cat.fuss as never, 140)).toBe(true)
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
    expect(dancing("sit", { kind: "pat", from: { x: 0, y: 0 }, until: 999 } as never, 140)).toBe(false)
  })
})

describe("pet presets", () => {
  test("absent file is the default preset: Nina classic, Argos", () => {
    expect(resolvePets(undefined)).toEqual(DEFAULT_PETS)
    expect(DEFAULT_PETS.cat.temperament).toEqual(TEMPERAMENTS.classic)
  })
  test("a file is a preset plus overrides — only the change is read", () => {
    const p = resolvePets({ preset: "nina-and-argos", cat: { temperament: "zen", name: "Mimi" } })
    expect(p.cat.name).toBe("Mimi"); expect(p.cat.temperament).toEqual(TEMPERAMENTS.zen); expect(p.dog.name).toBe("Argos")
  })
  test("axes are clamped and junk is ignored", () => {
    expect(resolvePets({ cat: { temperament: { warmth: 9, wits: "x", energy: -9 } } } as never).cat.temperament).toEqual({ warmth: 2, wits: 0, energy: -2 })
  })
  test("an unknown preset, species or temperament name falls back", () => {
    const p = resolvePets({ preset: "nope", cat: { species: "dragon", temperament: "nope" } } as never)
    expect(p).toEqual(DEFAULT_PETS)
  })
})

describe("the pet card's preview", () => {
  const S = (warmth: number, wits: number, energy: number) => ({ ...DEFAULT_PETS.cat, temperament: { warmth, wits, energy } })
  const asleep = (s: ReturnType<typeof S>) => { let n = 0; for (let t = 0; t < 400; t += 10) if (previewOf(s, t).mode === "sleep") n++; return n }
  test("it is a pure function of the pet and the tick", () => {
    for (const t of [0, 10, 95, 390]) expect(previewOf(S(0, 0, 0), t)).toEqual(previewOf(S(0, 0, 0), t))
  })
  test("a lazy pet is asleep more often than a playful one", () => {
    expect(asleep(S(0, 0, -2))).toBeGreaterThan(asleep(S(0, 0, 2)))
  })
  test("a cold pet speaks only in Nina's own voice; a warm one eventually goes sweet", () => {
    const all = [...Object.values(NINA).flatMap((v) => (Array.isArray(v) ? v : []))] as string[]
    const sweet = Object.values(SWEET).flat() as string[]
    for (let t = 0; t < 2000; t += 10) expect(all).toContain(previewOf(S(-2, 0, 0), t).line)
    expect([...Array(200).keys()].some((i) => sweet.includes(previewOf(S(2, 0, 0), i * 10).line))).toBe(true)
  })
})

describe("axis helpers", () => {
  test("dots shows the axis as a position among five", () => {
    expect([-2, -1, 0, 1, 2].map(dots)).toEqual(["●○○○○", "○●○○○", "○○●○○", "○○○●○", "○○○○●"])
  })
  test("cycleAxis steps forward and wraps", () => {
    expect(cycleAxis(-2)).toBe(-1); expect(cycleAxis(1)).toBe(2); expect(cycleAxis(2)).toBe(-2)
  })
})
