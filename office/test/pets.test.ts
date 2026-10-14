import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { dancing, furOf } from "../kit/draw"
import { ARGOS, cycleAxis, DEFAULT_PETS, dots, previewOf, resolvePets, SLOT_SPECIES, slotOf, SPECIES, speciesBase, SPECIES_VOICE, stepDog, TEMPERAMENTS } from "../kit/pets"
import { bucketFor, NINA, SWEET } from "../kit/voices"
import { CAT, DOG, fillArt, SPECIES_ART } from "../kit/sprites"
import { ROLE } from "../kit/palette"
import { EMPTY, type Agents } from "../kit/types"
import { EVENT_KINDS } from "../kit/events"
import { WideRoom, widePlan } from "../rooms/wide"
import { DOOR, RIM_FLOOR } from "../kit/bathroom"

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
    for (const [name, frames] of [...Object.entries(CAT), ...Object.entries(DOG), ...Object.values(SPECIES_ART).flatMap((a) => Object.entries(a))]) for (const rows of frames) {
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

  test("once every server line is said, they come round again rather than the canned ones", () => chance(0.999, () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
    room.hear({ Nina: { pet: ["Adore me.", "Kneel."] } })
    room.step(a)
    for (let i = 0; i < 6; i++) { room.pet(); expect(["Adore me.", "Kneel."]).toContain(pets.cat.said!) }
  }))

  test("the pair's exchange is said turn by turn, each in its own pet's balloon, none overwritten early", () => {
    const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1)
    const r = room as unknown as Pets & { talkOut(o: string): boolean }
    room.hear({ duo: { chat: [["Argos: Sing, O Muse, of Souls step 1!", "Nina: It shipped, darling. Calm yourself.", "Argos: TROY!"]] } })
    expect(r.talkOut("chat")).toBe(true)
    const heard: string[] = []
    chance(0.999, () => { for (let i = 0; i < 200; i++) { room.step(a); for (const s of [r.dog.said, r.cat.said]) if (s && !heard.includes(s)) heard.push(s) } })
    expect(heard).toEqual(["Sing, O Muse, of Souls step 1!", "It shipped, darling. Calm yourself.", "TROY!"])
    expect(r.talkOut("sneak")).toBe(false)
  })
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

describe("the cat slot's species", () => {
  const POSES = { sit: 3, walk: 4, sleep: 2, play: 2, stretch: 1, groom: 2, blink: 1 } as const
  test("every species has the frames drawCat reads, and no collar gems", () => {
    for (const [sp, art] of Object.entries(SPECIES_ART)) for (const [pose, n] of Object.entries(POSES)) {
      const frames = (art as Record<string, string[][]>)[pose]!
      if (["cat", "rabbit", "bird", "hamster", "baoaqu"].includes(sp)) expect({ sp, pose, n: frames.length }).toEqual({ sp, pose, n })
      else expect({ sp, pose, ok: frames.length > 0 }).toEqual({ sp, pose, ok: true })
      if (sp !== "cat") for (const rows of frames) expect(rows.join("")).not.toMatch(/[gj]/)
    }
  })
  test("each species' destination table sums to 1 and stays positive", () => {
    for (const sp of ["cat", "rabbit", "bird"] as const) {
      const w = Object.values(speciesBase(sp))
      expect(w.reduce((a, b) => a + b, 0)).toBeCloseTo(1, 10)
      for (const v of w) expect(v).toBeGreaterThan(0)
    }
    expect(speciesBase("bird").perch).toBeGreaterThan(speciesBase("rabbit").perch)
  })
  test("the cat slot takes cat, rabbit or bird; the dog slot stays a dog", () => {
    expect(resolvePets({ cat: { species: "bird" } }).cat.species).toBe("bird")
    expect(resolvePets({ cat: { species: "rabbit" } }).cat.species).toBe("rabbit")
    expect(resolvePets({ dog: { species: "bird" } } as never).dog.species).toBe("dog")
  })
  test("rabbit and bird talk in their own voices", () => {
    for (const sp of ["rabbit", "bird"] as const) for (const occ of ["pet", "muse", "wake", "done"] as const) {
      const v = SPECIES_VOICE[sp]
      expect(v.sassy[occ]!.length).toBeGreaterThan(0); expect(v.sweet[occ]!.length).toBeGreaterThan(0)
    }
  })
})

describe("every species is data", () => {
  test("art, exactly one slot, a destination table, a voice that falls back to Nina", () => {
    for (const sp of SPECIES) {
      const slot = slotOf(sp)
      expect({ sp, sits: ((SPECIES_ART as Record<string, { sit: string[][] } | undefined>)[sp]?.sit.length ?? 0) > 0 }).toEqual({ sp, sits: true })
      expect({ sp, slots: ["cat", "dog"].filter((s) => (SLOT_SPECIES as Record<string, readonly string[]>)[s]!.includes(sp)).length }).toEqual({ sp, slots: 1 })
      if (slot !== "cat") continue
      const art = (SPECIES_ART as Record<string, Record<string, string[][]>>)[sp]!
      for (const pose of ["sit", "blink", "groom", "walk", "sleep", "stretch", "play"]) expect({ sp, pose, ok: art[pose]!.length > 0 }).toEqual({ sp, pose, ok: true })
      expect(Object.values(speciesBase(sp)).reduce((a, b) => a + b, 0)).toBeCloseTo(1, 10)
      const neutral = { warmth: 0, wits: 0, energy: 0 }
      expect(bucketFor("read", neutral, () => 0, sp)).toBe(bucketFor("read", neutral, () => 0, "cat"))
    }
  })
  test("a pose a species does not draw falls back to its sit, at any index", () => {
    const art = fillArt({ sit: [["kk"]] })
    expect(art.walk).toBe(art.sit)
  })
  test("hamster ships: shelved, cat slot, draws in the room", () => {
    expect(SPECIES).toContain("hamster")
    expect(slotOf("hamster")).toBe("cat")
    expect(resolvePets({ cat: { species: "hamster" } }).cat.species).toBe("hamster")
    expect(bucketFor("pet", { warmth: 0, wits: 0, energy: 0 }, () => 0, "hamster")).toBe(SPECIES_VOICE.hamster.sassy.pet!)
    chance(0.999, () => {
      const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1)
      room.setPets(resolvePets({ cat: { species: "hamster" } }))
      for (let i = 0; i < 120; i++) { room.step(a); room.render(a, focus, measure) }
    })
  })
  test("the pet rock ships: a single pose, every other pose is its sit, it barely moves", () => {
    expect(SPECIES).toContain("rock")
    expect(slotOf("rock")).toBe("cat")
    expect(resolvePets({ cat: { species: "rock" } }).cat.species).toBe("rock")
    expect(SPECIES_ART.rock.walk).toBe(SPECIES_ART.rock.sit)
    expect(bucketFor("pet", { warmth: 0, wits: 0, energy: 0 }, () => 0, "rock")).toBe(SPECIES_VOICE.rock.sassy.pet!)
    expect(speciesBase("rock").nap).toBeGreaterThanOrEqual(0.8)
    chance(0.999, () => {
      const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1)
      room.setPets(resolvePets({ cat: { species: "rock" } }))
      for (let i = 0; i < 120; i++) { room.step(a); room.render(a, focus, measure) }
    })
  })
  test("A Bao A Qu ships: Borges' slow climber, cat slot, three sits and four walks", () => {
    expect(SPECIES).toContain("baoaqu")
    expect(slotOf("baoaqu")).toBe("cat")
    expect(resolvePets({ cat: { species: "baoaqu" } }).cat.species).toBe("baoaqu")
    expect(SPECIES_ART.baoaqu.sit).toHaveLength(3)
    expect(SPECIES_ART.baoaqu.walk).toHaveLength(4)
    expect(bucketFor("pet", { warmth: 0, wits: 0, energy: 0 }, () => 0, "baoaqu")).toBe(SPECIES_VOICE.baoaqu.sassy.pet!)
    expect(speciesBase("baoaqu").perch).toBeGreaterThan(speciesBase("cat").perch)
    chance(0.999, () => {
      const room = new WideRoom(560), a = viewOf(office({ thinking: false }), 1)
      room.setPets(resolvePets({ cat: { species: "baoaqu" } }))
      for (let i = 0; i < 120; i++) { room.step(a); room.render(a, focus, measure) }
    })
  })
})

describe("the preview speaks in the species' voice", () => {
  test("a hamster's preview lines are the hamster's, never Nina's", () => {
    const v = SPECIES_VOICE.hamster, own = [...v.sassy.pet, ...v.sassy.muse, ...v.sweet.pet, ...v.sweet.muse]
    for (let t = 0; t < 400; t += 10) expect(own).toContain(previewOf({ name: "Biscuit", species: "hamster", temperament: { warmth: 2, wits: 0, energy: 0 } }, t).line)
  })
  test("a dog's preview lines are the dog's, never Nina's", () => {
    const v = SPECIES_VOICE.dog, own = [...v.sassy.pet, ...v.sassy.muse, ...v.sweet.pet, ...v.sweet.muse]
    for (const warmth of [-2, 2]) for (let t = 0; t < 400; t += 10) expect(own).toContain(previewOf({ name: "Rex", species: "dog", temperament: { warmth, wits: 0, energy: 0 } }, t).line)
  })
})

describe("a pet's shade", () => {
  test("a shade lightens the fur and never leaves 0..3", () => {
    expect(furOf(0)).toBe(ROLE.fieldInk)
    expect(new Set([0, 1, 2, 3].map(furOf)).size).toBe(4)
    expect(resolvePets({ cat: { shade: 2 } }).cat.shade).toBe(2)
    expect(resolvePets({ cat: { shade: 9 } }).cat.shade).toBe(0)
    expect(resolvePets({ cat: { shade: 1.5 } } as never).cat.shade).toBe(0)
    expect(resolvePets(undefined).dog.shade).toBe(0)
  })
})

describe("Argos and the trail", () => {
  type Trail = { dog: { x: number; y: number; path: { x: number; y: number }[]; mode: string; creep: boolean; until: number; fuss: unknown }; prints: { x: number; y: number; at: number; until: number }[]; tick: number }
  const trail = [300, 312, 324].map((x, i) => ({ x, y: 188, at: i * 12, until: 9999 }))

  test("he follows the prints in the order she laid them, creeping", () => chance(0, () => {
    const room = new WideRoom(696), a = viewOf(office({ thinking: false }), 1), r = room as unknown as Trail
    for (let i = 0; i < 10; i++) room.step(a)
    r.prints = trail.map((p) => ({ ...p }))
    Object.assign(r.dog, { until: 0, mode: "sit", fuss: null, path: [] })
    for (let i = 0; i < 40 && !r.dog.creep; i++) room.step(a)
    expect(r.dog.creep).toBe(true)
    expect(r.dog.path.slice(-3).map((p) => [p.x, p.y])).toEqual([[300, 188], [312, 188], [324, 188]])
  }))

  test("a trail from the tub takes him in by the door, never through the bathroom's wall", () => chance(0, () => {
    const room = new WideRoom(696), a = viewOf(office({ thinking: false }), 1), r = room as unknown as Trail
    const plan = widePlan(696), blocks = plan.blocks(plan.layout(a))
    for (let i = 0; i < 10; i++) room.step(a)
    r.prints = [RIM_FLOOR, { x: RIM_FLOOR.x + 12, y: RIM_FLOOR.y + 2 }, { x: DOOR.x, y: DOOR.y - 2 }].map((p, i) => ({ ...p, at: i * 12, until: 9999 }))
    Object.assign(r.dog, { until: 0, mode: "sit", fuss: null, path: [] })
    for (let i = 0; i < 40 && !r.dog.creep; i++) room.step(a)
    expect(r.dog.creep).toBe(true)
    const path = [{ x: r.dog.x, y: r.dog.y }, ...r.dog.path]
    for (let i = 1; i < path.length; i++) {
      const [p, q] = [path[i - 1]!, path[i]!]
      for (let x = p.x, y = p.y; x !== q.x || y !== q.y; x += Math.sign(q.x - x), y += Math.sign(q.y - y)) {
        // inclusive: the bathroom's walls are two pixels wide, and an interior-only check never sees them
        const hit = blocks.find((b) => x >= b.x && x < b.x + b.w && y >= b.y && y < b.y + b.h)
        expect({ at: [x, y], hit }).toEqual({ at: [x, y], hit: undefined })
      }
    }
  }))

  test("one print is not a trail, and no prints leave his day as it was", () => chance(0, () => {
    const dog = { x: 200, y: 176, aisle: 176, path: [], mode: "sit" as const, until: 0, face: -1, woof: 0, host: null, creep: false, said: null, saidFrom: 0, saidUntil: 0, belly: 0, fuss: null }
    const ctx = (prints: { x: number; y: number }[]) => ({
      tick: 100, antic: null, quiet: () => true, actors: new Map(), at: () => [], bed: () => ({ x: 400, y: 112, aisle: 112, pose: "stand" as const, face: "left" as const, kind: "roam" as const }),
      bowl: () => ({ x: 500, y: 162, aisle: 162, pose: "stand" as const, face: "right" as const, kind: "roam" as const }),
      visit: () => { throw new Error("no host") }, roam: () => ({ x: 150, y: 176, aisle: 176, pose: "stand" as const, face: "left" as const, kind: "roam" as const }),
      route: (x: number, _from: number, goal: { x: number; y: number }) => [{ x, y: goal.y }, { x: goal.x, y: goal.y }],
      table: () => ({ x: 0, y: 0, w: 1, h: 1 }), mc: 300, say: () => {}, argos: () => "", fussDog: () => {}, prints: () => prints,
    })
    expect(stepDog({ ...dog, path: [] }, ctx([]) as never)).toBe(true)
    const one = { ...dog, path: [] as { x: number; y: number }[] }
    stepDog(one, ctx([trail[0]!]) as never)
    expect(one.creep).toBe(false)
  }))
})

describe("the pets react to events", () => {
  test("Nina and Argos each say a line of their own for every kind of event", () => chance(0.999, () => {
    for (const kind of EVENT_KINDS) {
      const room = new WideRoom(696), a = viewOf(office({ thinking: false }), 1), pets = room as unknown as Pets
      for (let i = 0; i < 300; i++) room.step(a)
      expect(room.event(kind)).toBe(true)
      const cat = new Set<string>(), dog = new Set<string>()
      for (let i = 0; i < 300; i++) {
        room.step(a)
        if (pets.cat.said) cat.add(pets.cat.said)
        if (pets.dog.said) dog.add(pets.dog.said)
      }
      if (kind !== "drill") {
        const nina = [...NINA[`event_${kind}`], ...(SWEET[`event_${kind}`] ?? [])]
        expect([kind, nina.some((l) => cat.has(l))]).toEqual([kind, true])
      }
      expect([kind, ARGOS[`event_${kind}`].some((l) => dog.has(l))]).toEqual([kind, true])
    }
  }))
  test("Argos is overjoyed at the zoo", () => {
    expect(ARGOS.event_zoo.some((l) => /ANIMALS/.test(l))).toBe(true)
  })
})
