// The wide room: the office as the TUI draws it, as wide as the terminal. Under one long back wall —
// the whiteboard with its titles readable, the notes corkboard, windows on the real sky, a clock, the
// TV — four zones side by side: your office (Nina's corner too), the open floor (the manager's and
// the lead's desks, the crew board, two tables of four), a glass meeting room, the lounge with its
// kitchen. A hallway runs along the bottom; every zone has one lane down to it, and every walk goes
// lane → hallway → lane, so nobody needs a path finder and nobody walks through a desk.
import { balloonLines, fit, type Frame, type Measure } from "../kit/canvas"
import { boardColumns, COLS, isManager, needsYou, peopleOf, tipOf } from "../kit/crew"
import { drawActors, drawCat, drawFuss, Scene, type Focus } from "../kit/draw"
import { bossDesk, crewBoard, decor, execDesk } from "../kit/furniture"
import { ROLE, tint } from "../kit/palette"
import { FUSS, Sim, keyOf, type Actor, type Fussing, type Plan, type Pt, type Spot } from "../kit/sim"
import { pick, type Fuss } from "../kit/voices"
import { hueRole, Tv } from "../kit/tv"
import { BIG_PLANT, COFFEE, COOLER, DOG, DOG_NAME, SCRIBBLES, shirtOf } from "../kit/sprites"
import { EMPTY, type Agents, type Seat } from "../kit/types"

export const WIDE_H = 200
/** below this the zones don't fit; a surface narrower than this draws the rail room */
export const WIDE_MIN_W = 540
const BAND = 44 // the back wall ends here
const HALL = 191 // the hallway's walking row
const OFF_W = 100, OFF_LANE = 94, OFF_DOOR = 150 // your office; its glass wall stops at the door
const MEET_MIN = 86, MEET_BOTTOM = 124, LOUNGE_MIN = 124
const EXEC_Y = 54, TABLE_YS = [102, 142], SEATS = 4, SEAT_GAP = 28
const CREW_W = 44, EXEC_W = 56

/** the zones' edges for a room `w` wide: width past the minimum goes mostly to the floor, and the whiteboard above it */
function zones(w: number) {
  const extra = Math.max(0, w - WIDE_MIN_W)
  const MW = MEET_MIN + 2 * Math.floor(extra * 0.1), LW = LOUNGE_MIN + Math.floor(extra * 0.25)
  const L0 = w - LW, M0 = L0 - 6 - MW, F0 = OFF_W + 6, F1 = M0 - 6
  return { L0, M0, MW, Mc: M0 + MW / 2, F0, F1 }
}
type Zones = ReturnType<typeof zones>
/** a zone's lane: the column it walks down to the hallway */
function laneOf(z: Zones, x: number) {
  return x <= OFF_W ? OFF_LANE : x < z.M0 ? z.F0 + 3 : x < z.L0 ? z.Mc : z.L0 + 6
}

type Desk = { x: number; y: number; w: number; kind: "boss" | "manager" | "lead"; seat?: Seat }
type Chair = { x: number; table: number; agent: string | null }
const seatX = (d: Desk) => d.x + Math.round(d.w / 2)

function layoutFor(z: Zones) {
  return (a: Agents) => {
    const desks: Desk[] = [{ x: 24, y: 56, w: 52, kind: "boss" }]
    const people = peopleOf(a)
    const managers = people.filter((p) => isManager(a, p)), workers = people.filter((p) => !isManager(a, p))
    if (managers[0]) desks.push({ x: z.F0 + CREW_W + 12, y: EXEC_Y, w: EXEC_W, kind: "manager", seat: managers[0] })
    const lead = workers.find((p) => p.lead), grunts = workers.filter((p) => p !== lead)
    if (lead) desks.push({ x: z.F0 + CREW_W + EXEC_W + 16, y: EXEC_Y, w: EXEC_W, kind: "lead", seat: lead })
    const chairs: Chair[] = []
    TABLE_YS.forEach((ty, t) => {
      for (let i = 0; i < SEATS; i++) chairs.push({ x: z.F0 + 24 + i * SEAT_GAP, table: ty, agent: grunts[t * SEATS + i]?.agent ?? null })
    })
    return { desks, chairs, people }
  }
}
type Layout = ReturnType<ReturnType<typeof layoutFor>>

// Nina's corner of your office: the tower by the glass, the litter box by the left wall, the yarn
// and a mouse on the rug
const TOWER_X = 78, PERCH_TOP = { x: 83, y: 52 }, PERCH_MID = { x: 83, y: 69 }
const CAT_NAP = { x: 50, y: 128 }, CAT_DESK = { x: 37, y: 75 }, LITTER = { x: 7, y: 98 }, PLAY = { x: 70, y: 132 }
const YARN = { x: 76, y: 130 }, MOUSE = { x: 24, y: 134 }
// your in-tray, on a side table left of your desk
const TRAY = { x: 4, y: 62 }

/** the plan, and the furniture's footprints (for the route test): every rectangle no feet may enter */
export function widePlan(w: number): Plan<Layout> & { blocks: (l: Layout) => { x: number; y: number; w: number; h: number }[] } {
  const z = zones(w)
  const { L0, M0, MW, Mc, F0, F1 } = z
  const inOffice = (x: number) => x <= OFF_W
  return {
    layout: layoutFor(z),
    home(l, agent) {
      const m = l.desks.find((d) => (d.kind === "manager" || d.kind === "lead") && d.seat?.agent === agent)
      if (m) return { x: seatX(m), y: m.y + 19, aisle: m.y - 3, pose: "sit", face: "down", kind: "desk" }
      const c = l.chairs.find((x) => x.agent === agent)
      return c ? { x: c.x, y: c.table + 26, aisle: c.table + 34, pose: "sit", face: "up", kind: "desk" } : null
    },
    // whoever has a question for you stands in front of your desk; the rest wait behind them
    queue: [
      ...[48, 60, 72, 84].map((x, i): Spot => ({ x, y: 148, aisle: 148, pose: "stand", face: i === 0 ? "up" : "left", kind: "queue" })),
      { x: 88, y: 164, aisle: 164, pose: "stand", face: "up", kind: "queue" },
    ],
    // the lounge's couch (facing the TV up on the wall), its beanbag, the kitchen counter
    lounge: [
      { x: L0 + 44, y: 82, aisle: 94, pose: "couch", face: "up", kind: "couch" },
      { x: L0 + 60, y: 82, aisle: 94, pose: "couch", face: "up", kind: "couch" },
      { x: L0 + 76, y: 82, aisle: 94, pose: "couch", face: "up", kind: "couch" },
      { x: L0 + 30, y: 150, aisle: 150, pose: "couch", face: "up", kind: "couch" },
      { x: w - 26, y: 116, aisle: 116, pose: "stand", face: "right", kind: "cooler" },
      { x: w - 26, y: 136, aisle: 136, pose: "stand", face: "right", kind: "coffee" },
    ],
    // the meeting room's table, two laptops a side: where the warm but unbusy sit, on call
    oncall: [Mc - 22, Mc + 22].flatMap((x) => [81, 95].map((y): Spot => ({ x, y, aisle: 116, pose: "sit", face: x < Mc ? "right" : "left", kind: "laptop" }))),
    exit: { x: w - 3, y: HALL, aisle: HALL, pose: "stand", face: "right", kind: "exit" },
    pen: { x: F1 - 30, y: 51, aisle: 51, pose: "stand", face: "up", kind: "note" },
    /** beside whoever is visited: in front of a desk that faces the room, beside a seat at a table, else where they stand */
    visit(h: Actor): Spot {
      const at = h.spot.kind === "desk" && !h.path.length
      if (at && h.spot.face === "down") return { x: h.x, y: h.spot.y + 16, aisle: h.spot.y + 16, pose: "stand", face: "up", kind: "visit" }
      if (at) return { x: h.x + SEAT_GAP / 2, y: h.spot.y, aisle: h.spot.aisle, pose: "stand", face: "left", kind: "visit" }
      return { x: Math.min(w - 10, h.x + 12), y: h.y, aisle: h.y, pose: "stand", face: "left", kind: "visit" }
    },
    // the lounge is full: a stroll along the floor's back aisle
    roam: () => ({ x: F0 + 10 + Math.floor(Math.random() * Math.max(1, F1 - F0 - 20)), y: 176, aisle: 176, pose: "stand", face: "down", kind: "roam" }),
    route(x, from, goal) {
      const la = laneOf(z, x), lb = laneOf(z, goal.x)
      const there = [{ x: lb, y: goal.aisle }, { x: goal.x, y: goal.aisle }, { x: goal.x, y: goal.y }]
      if (la === lb) return [{ x, y: from }, { x: la, y: from }, ...there]
      return [{ x, y: from }, { x: la, y: from }, { x: la, y: HALL }, { x: lb, y: HALL }, ...there]
    },
    cat: {
      nap: CAT_NAP, desk: CAT_DESK, play: PLAY, litter: LITTER, perches: [PERCH_TOP, PERCH_MID],
      // the zoomies: your office (your desk, her tower) and the lounge (the couch back, the top of
      // the TV, the kitchen counter), each first the floor spot she lands on after
      leaps: [
        [CAT_NAP, CAT_DESK, PERCH_TOP, PERCH_MID, { x: 18, y: 112 }, { x: 72, y: 142 }],
        [{ x: L0 + 52, y: 104 }, { x: L0 + 46, y: 69 }, { x: L0 + 80, y: 69 }, { x: L0 + 58, y: 7 }, { x: w - 7, y: 99 }, { x: L0 + 100, y: 140 }],
      ],
      lounge: [{ x: L0 + 52, y: 104 }, { x: w - 40, y: 126 }],
      spots: [CAT_NAP, { x: 24, y: 140 }, { x: 40, y: 104 }, CAT_DESK, PERCH_TOP, PERCH_MID, PLAY, { x: L0 + 52, y: 104 }],
      via: (p: Pt) =>
        p.x === CAT_DESK.x && p.y === CAT_DESK.y ? { x: CAT_DESK.x, y: 100 }
          : p.x === PERCH_TOP.x && p.y <= PERCH_MID.y ? { x: PERCH_TOP.x, y: 94 }
            : p.x === LITTER.x && p.y === LITTER.y ? { x: LITTER.x, y: 106 } : null,
      // out through your office's door and along the hallway, when she changes rooms
      door: (from, to) => {
        if (inOffice(from.x) === inOffice(to.x)) return []
        const office = [{ x: OFF_LANE, y: 160 }, { x: OFF_LANE, y: HALL - 3 }], lounge = [{ x: L0 + 6, y: HALL - 3 }, { x: L0 + 6, y: to.y }]
        return inOffice(from.x) ? [...office, ...lounge] : [{ x: L0 + 6, y: HALL - 3 }, { x: OFF_LANE, y: HALL - 3 }, { x: OFF_LANE, y: 160 }]
      },
    },
    blocks(l) {
      const out = [
        { x: 0, y: 0, w, h: BAND }, // the back wall
        { x: TOWER_X, y: 40, w: 12, h: 48 }, // the cat tower
        { x: M0 - 1, y: BAND, w: 2, h: MEET_BOTTOM - BAND }, { x: M0 + MW - 1, y: BAND, w: 2, h: MEET_BOTTOM - BAND }, // the meeting room's glass
        { x: M0, y: MEET_BOTTOM - 1, w: MW / 2 - 9, h: 2 }, { x: Mc + 9, y: MEET_BOTTOM - 1, w: MW / 2 - 9, h: 2 },
        { x: Mc - 14, y: 76, w: 28, h: 20 }, // its table
        { x: L0 + 34, y: 68, w: 54, h: 10 }, // the couch's back
        { x: w - 14, y: 100, w: 14, h: 56 }, // the kitchen counter
        { x: F0 + 8, y: EXEC_Y, w: CREW_W, h: 32 }, // the crew board
        { x: F1 - 40, y: 150, w: 14, h: 24 }, // the filing cabinet
        { x: F1 - 60, y: 146, w: 12, h: 28 }, // the server rack
        { x: TRAY.x, y: TRAY.y, w: 16, h: 14 }, // the in-tray's table
        { x: OFF_W - 1, y: BAND, w: 2, h: OFF_DOOR - BAND }, // your office's glass
      ]
      for (const d of l.desks) out.push({ x: d.x, y: d.y + 2, w: d.w, h: 29 })
      for (const ty of TABLE_YS) out.push({ x: F0 + 14, y: ty + 3, w: SEATS * SEAT_GAP + 4, h: 20 })
      return out
    },
  }
}

/**
 * What Argos says, by occasion. He is the troglodyte of Borges' "The Immortal" who turned out to be
 * Homer: an epic poet, mostly forgotten, now overwhelmingly a good boy.
 */
const ARGOS = {
  pat: ["Good boy? Me? Yes. ME!", "Sing, O Muse, of this scratch behind the ears.", "I have known gods. None pat like you."],
  belly: ["Belly! The WHOLE belly! In twenty-four books!", "Rub the belly and I shall sing of it forever."],
  muse: ["I once sang of Troy. Now I sing of squirrels.", "Rosy-fingered dawn means breakfast, right?", "Wine-dark sea. Water-dark bowl. Same thing.", "Every dog is all dogs. I still want the ball.", "Nine years at Troy. Nine minutes for a walk?", "The Immortal fears nothing. Except the vacuum."],
  test: ["Fetch the tests! FETCH!", "Tests! Can I chase them? Can I?"],
  done: ["Turn's done? WALK? Is it walk time?", "{name} finished! I'm so proud I could howl."],
  queue: ["Someone's waiting! I will guard them.", "{name} needs the boss! I'll fetch!"],
  visit: ["You look like you need a dog, {name}.", "Hello {name}! I brought my whole self."],
  walk: ["WALK!! The best word in any language!"],
  office: ["Coming! Coming coming coming."],
  sit: ["Sitting. Very good sitting. Epic, even."],
  bed: ["An epic nap, in twenty-four books."],
  fuss: {
    pat: ["Yes! The head! The good head!", "Thank you, {name}! Thank you thank you!"],
    scratch: ["Ohh, the ear. The leg's going. Can't stop it.", "There! THERE! O, {name}, there!"],
    belly: ["The belly! Achilles never got this!"],
    treat: ["A TREAT! I'd sail to Ithaca for this!", "Nom! {name} is my favourite! Everyone is!"],
  } satisfies Record<Fuss, string[]>,
}

/**
 * Argos: where he is, the waypoints he is walking, what he is doing, the row he walks along; what
 * he is saying until `saidUntil`; `belly` the tick his roll-over for a rub ends; `fuss` someone
 * making a fuss of him
 */
type Dog = { x: number; y: number; aisle: number; path: Pt[]; mode: "walk" | "sit" | "sleep"; until: number; face: number; woof: number; host: string | null; creep: boolean; said: string | null; saidFrom: number; saidUntil: number; belly: number; fuss: Fussing | null }
/** Nina and Argos, up to something together */
type Antic = { kind: "sneak" | "bap" | "chase" | "scuffle"; until: number; trail: Pt[]; lap: Pt[] }

export class WideRoom extends Sim<Layout> {
  private readonly z: Zones
  private readonly tvSet = new Tv(48, 28)
  private readonly dog: Dog
  private antic: Antic | null = null
  constructor(readonly width: number) {
    super(widePlan(width))
    this.z = zones(width)
    const bed = this.dogBed()
    this.dog = { x: bed.x, y: bed.y, aisle: bed.aisle, path: [], mode: "sleep", until: 200, face: -1, woof: 0, host: null, creep: false, said: null, saidFrom: 0, saidUntil: 0, belly: 0, fuss: null }
  }
  /** Argos says something (after `delay`, when he is answering) */
  private dogSay(text: string, delay = 0) { const d = this.dog; d.said = text; d.saidFrom = this.tick + delay; d.saidUntil = d.saidFrom + 45 }
  /** Argos' line for an occasion: the model's, else his own (`ARGOS`) */
  private argos(occasion: keyof typeof ARGOS | `fuss_${Fuss}`, name = "") {
    const canned = occasion.startsWith("fuss_") ? ARGOS.fuss[occasion.slice(5) as Fuss] : ARGOS[occasion as Exclude<keyof typeof ARGOS, "fuss">]
    return this.line("Argos", occasion, canned, name)
  }
  /** someone starts a tool, finishes a turn, or joins your queue: Nina's opinion, then Argos' */
  protected override noticed(actor: Actor, what: string) {
    super.noticed(actor, what)
    if ((what === "test" || what === "done" || what === "queue") && this.quiet(this.dog.saidUntil) && Math.random() < 0.3) this.dogSay(this.argos(what, actor.seat.agent))
  }

  /** his bed by the lounge's couch, his water bowl by the kitchen */
  private dogBed(): Spot { return { x: this.z.L0 + 108, y: 112, aisle: 112, pose: "stand", face: "left", kind: "roam" } }
  private dogBowl(): Spot { return { x: this.width - 26, y: 162, aisle: 162, pose: "stand", face: "right", kind: "roam" } }

  /** you tell Argos where to go — his bed, a turn round the floor, your office — or to sit where he is */
  dogDo(what: "bed" | "walk" | "office" | "sit") {
    const d = this.dog
    if (what === "sit") { d.path = []; d.mode = "sit"; d.until = this.tick + 300; d.aisle = d.y; return }
    const spot = (x: number, y: number): Spot => ({ x, y, aisle: y, pose: "stand", face: "left", kind: "roam" })
    const goal = what === "bed" ? this.dogBed() : what === "office" ? spot(60, 140) : this.plan.roam(this.plan.layout(EMPTY))
    d.host = null; d.creep = false
    d.path = [{ x: d.x, y: d.aisle }, ...this.plan.route(d.x, d.aisle, goal)]
    d.aisle = goal.aisle; d.mode = "walk"
    this.dogSay(this.argos(what))
  }

  /** a click on Argos: a woof and a wag — and if he's not off somewhere, over he rolls for a belly rub */
  patDog() {
    const d = this.dog
    d.woof = this.tick + 25
    if (d.mode === "sleep") { d.mode = "sit"; d.until = this.tick + 120 }
    if (!d.path.length) { d.belly = this.tick + 30; this.dogSay(this.argos("belly")) } else this.dogSay(this.argos("pat"))
  }
  /** someone at `from` makes a fuss of Argos */
  private fussDog(by: Actor) {
    const d = this.dog, kind = pick<Fuss>(["pat", "scratch", "belly", "treat"])
    d.fuss = { kind, from: { x: by.x, y: by.y }, until: this.tick + FUSS }
    if (kind === "belly") d.belly = this.tick + FUSS
    d.mode = "sit"; d.until = Math.max(d.until, this.tick + FUSS + 40)
    by.emote = "♥"; by.emoteUntil = this.tick + FUSS
    this.dogSay(this.argos(`fuss_${kind}`, by.seat.agent))
  }

  /**
   * Argos' day: naps in his bed, drinks, trots the floor, sits by someone at their desk (they get a
   * ♥), drops in on your office, lies in the meeting room. He walks the people's routes, so he keeps off the furniture too.
   */
  private stepDog(): boolean {
    const d = this.dog
    if (d.fuss && this.tick >= d.fuss.until) d.fuss = null
    if (this.tick < d.belly) return false
    if (d.path.length) {
      if (d.creep && this.tick % 3) return false
      const to = d.path[0]!
      d.x += Math.sign(to.x - d.x); d.y += Math.sign(to.y - d.y)
      if (to.x !== d.x) d.face = Math.sign(to.x - d.x)
      if (d.x === to.x && d.y === to.y) d.path.shift()
      if (!d.path.length) {
        const bed = this.dogBed(), asleep = d.x === bed.x && d.y === bed.y
        d.mode = asleep ? "sleep" : "sit"
        d.until = this.tick + (asleep ? 900 : 200) + Math.floor(Math.random() * 400)
        const host = d.host ? this.actors.get(d.host) : undefined
        if (host) {
          // at their desk they reach down to him; or he just says hello
          if (Math.random() < 0.6) this.fussDog(host)
          else { host.emote = "♥"; host.emoteUntil = this.tick + 40; this.dogSay(this.argos("visit", host.seat.agent)) }
        }
      }
      return true
    }
    if (this.antic) return false
    // anyone idling in the lounge reaches down to him when he wanders close
    if (d.mode !== "sleep" && !d.fuss && Math.random() < 0.004) {
      const near = [...this.actors.values()].find((a) => !a.moving && !a.path.length && (a.spot.kind === "couch" || a.spot.kind === "cooler" || a.spot.kind === "coffee" || a.spot.kind === "roam") && Math.abs(a.x - d.x) < 22 && Math.abs(a.y - d.y) < 16)
      if (near) { this.fussDog(near); return true }
    }
    if (this.tick < d.until) return d.mode === "sit" && this.tick % 3 === 0
    const r = Math.random(), working = [...this.actors.values()].filter((a) => a.spot.kind === "desk" && !a.moving && !a.path.length)
    const host = working.length && r < 0.35 ? pick(working) : null
    const spot = (x: number, y: number, aisle = y): Spot => ({ x, y, aisle, pose: "stand", face: "left", kind: "roam" })
    const goal: Spot = host ? this.plan.visit(host)
      : r < 0.5 ? this.dogBed() : r < 0.6 ? this.dogBowl()
        : r < 0.72 ? spot(40 + Math.floor(Math.random() * 40), 140) // your office, where Nina is
          : r < 0.82 ? spot(this.z.Mc - 4, 110, 116)
            : this.plan.roam(this.plan.layout(EMPTY))
    d.host = host ? keyOf(host.seat) : null
    d.path = [{ x: d.x, y: d.aisle }, ...this.plan.route(d.x, d.aisle, goal)]
    d.aisle = goal.aisle; d.mode = "walk"
    return true
  }

  /**
   * The room's tick, and the TV's show at half its rate. Whoever's settled on the couch picks up the
   * remote now and then (about once a minute and a quarter each) and flips the channel.
   */
  override step(a: Agents): boolean {
    const moved = [this.stepDog(), this.stepAntics(), super.step(a)].some(Boolean)
    if (this.dog.mode !== "sleep" && this.quiet(this.dog.saidUntil) && Math.random() < 1 / 1800) this.dogSay(this.argos("muse"))
    if (this.tick % 2) return moved
    for (const x of this.actors.values()) {
      if (x.spot.kind !== "couch" || x.moving || Math.random() >= 1 / 375) continue
      this.tvSet.next(); x.emote = "*"; x.emoteUntil = this.tick + 20
      break
    }
    this.tvSet.step()
    return true
  }
  /** the remote: the next channel */
  channel() { this.tvSet.next() }

  render(a: Agents, focus: Focus, measure: Measure, now = new Date()): Frame {
    const W = this.width, H = WIDE_H
    const sc = new Scene(W, H, this.tick), f = sc.f
    const { L0, M0, MW, Mc, F0, F1 } = this.z
    const { desks, chairs } = this.plan.layout(a)
    const px = sc.px.bind(sc), blit = sc.blit.bind(sc), text = sc.text.bind(sc)
    const using = this.using.bind(this)

    // ── floors ──
    const tileA = tint(ROLE.prose, ROLE.ground, 0.27), tileB = tint(ROLE.prose, ROLE.ground, 0.21)
    for (let ty = BAND; ty < H; ty += 8) for (let tx = 0; tx < W; tx += 8) px(tx, ty, 8, 8, ((tx + ty) / 8) % 2 ? tileA : tileB)
    // your office: a carpet, flecked
    px(0, BAND, OFF_W, H - BAND, tint(ROLE.meta, ROLE.ground, 0.3))
    for (let y = BAND + 3; y < H; y += 3) for (let x = (y * 5) % 7; x < OFF_W; x += 7) px(x, y, 1, 1, tint(ROLE.meta, ROLE.ground, 0.4))
    // the meeting room's carpet, the lounge's boards
    px(M0, BAND, MW, MEET_BOTTOM - BAND, tint(ROLE.key, ROLE.ground, 0.18))
    const board = tint(ROLE.structure, ROLE.ground, 0.4), seam = tint(ROLE.structure, ROLE.ground, 0.22)
    px(L0, BAND, W - L0, H - BAND, board)
    for (let y = BAND + 3; y < H; y += 4) { px(L0, y, W - L0, 1, seam); px(L0 + 6 + ((y >> 2) % 3) * 19, y - 3, 1, 3, seam) }
    // the hallway's runner along the bottom, under every zone
    px(0, HALL - 6, W, 9, tint(ROLE.structure, ROLE.ground, 0.3)); px(0, HALL - 6, W, 1, tint(ROLE.body, ROLE.ground, 0.4))
    text("EXIT", W - 14, HALL - 8, ROLE.live, 11)

    // ── the back wall ──
    px(0, 0, W, BAND - 1, ROLE.edge); px(0, BAND - 1, W, 1, ROLE.structure)
    this.calendar(sc, 4, now, Object.values(a.calendar).flat())
    this.whiteboard(sc, a, measure, 62, F1 - 64)
    this.corkboard(sc, a, F1 - 58)
    this.windows(sc, M0 + 4, L0 + 30, now)
    this.tv(sc, L0 + 36)
    this.clock(sc, W - 24, now)

    // ── your office: glass on the floor's side, a door at the bottom; your desk; Nina's corner ──
    for (const y0 of [BAND]) { px(OFF_W - 1, y0, 1, OFF_DOOR - y0, ROLE.edge); px(OFF_W, y0, 1, OFF_DOOR - y0, ROLE.key) }
    px(14, 108, 72, 36, ROLE.body); px(15, 109, 70, 34, ROLE.meta)
    for (let i = 0; i < 7; i++) for (const [dx, dy, w] of [[1, 0, 1], [0, 1, 3], [1, 2, 1]] as const) px(20 + i * 9 + dx, 124 + dy, w, 1, ROLE.assistant)
    for (const d of desks) if (d.kind === "boss") bossDesk(sc, a, d)
    this.ninasCorner(sc)
    this.inTray(sc, focus.tray ?? 0)
    this.beacon(sc, Object.values(a.triage).reduce((n, x) => n + x, 0))
    sc.item(170, () => blit(BIG_PLANT, 2, 159, { l: ROLE.live, o: ROLE.structure }))

    // ── the floor: the crew board, the manager's and the lead's desks, two tables of four ──
    crewBoard(sc, a, measure, F0 + 8, EXEC_Y, CREW_W, 32, 9)
    for (const d of desks) {
      if (d.kind === "boss" || !d.seat) continue
      const owner = this.actors.get(keyOf(d.seat))
      execDesk(sc, a, measure, { ...d, kind: d.kind, seat: d.seat }, !!owner && owner.spot.kind === "desk" && !owner.path.length, 38)
    }
    for (const ty of TABLE_YS) this.table(sc, a, measure, ty, chairs.filter((c) => c.table === ty), focus)
    // what's left of the floor: plants along it, a printer, the filing cabinet (the finished work)
    if (F1 - F0 > 150) sc.item(TABLE_YS[0]! + 20, () => blit(BIG_PLANT, F1 - 14, TABLE_YS[0]! + 9, { l: ROLE.live, o: ROLE.structure }))
    if (F1 - F0 > 150) sc.item(176, () => { px(F1 - 20, 160, 16, 10, ROLE.inactive); px(F1 - 18, 158, 12, 2, ROLE.prose); px(F1 - 16, 170, 2, 4, ROLE.structure); px(F1 - 8, 170, 2, 4, ROLE.structure) })
    sc.item(174, () => {
      const cx = F1 - 40
      px(cx, 150, 14, 24, ROLE.inactive); px(cx, 150, 14, 1, ROLE.prose)
      for (const dy of [152, 160, 168]) { px(cx + 1, dy, 12, 6, tint(ROLE.inactive, ROLE.ground, 0.75)); px(cx + 5, dy + 2, 4, 1, ROLE.structure) }
      px(cx + 2, 167, 9, 1, ROLE.prose) // a folder left sticking out of the bottom drawer
    })
    sc.hits.push({ x: F1 - 40, y: 150, w: 14, h: 24, tip: "the filing cabinet: finished tickets and closed threads", act: { kind: "archive" } })
    this.rack(sc, a, F1 - 60)

    // ── the meeting room: glass, a round table, its chairs ──
    sc.item(BAND, () => {
      for (const x of [M0, M0 + MW - 1]) { px(x, BAND, 1, MEET_BOTTOM - BAND, ROLE.key) }
      px(M0, MEET_BOTTOM - 1, MW / 2 - 9, 1, ROLE.key); px(Mc + 9, MEET_BOTTOM - 1, MW / 2 - 9, 1, ROLE.key)
    })
    sc.item(96, () => {
      for (let dy = -10; dy <= 10; dy++) { const half = Math.round(Math.sqrt(100 - dy * dy) * 1.4); px(Mc - half, 86 + dy, half * 2, 1, dy < -8 ? ROLE.body : ROLE.borderInactive) }
      px(Mc - 3, 82, 6, 3, ROLE.prose); px(Mc + 6, 88, 3, 2, ROLE.attention) // papers, a mug
    })
    text("MEETING", Mc, BAND + 9, ROLE.key, 11)

    // ── the lounge: rug, couch (its back toward you), lamp, beanbag; the kitchen along the wall ──
    px(L0 + 34, 48, 54, 14, ROLE.structure); px(L0 + 35, 49, 52, 12, ROLE.borderInactive)
    for (let i = 0; i < 8; i++) px(L0 + 38 + i * 6, 52 + (i % 2) * 4, 2, 2, ROLE.meta)
    sc.item(82.5, () => {
      px(L0 + 34, 76, 56, 8, ROLE.structure); px(L0 + 35, 77, 54, 1, ROLE.borderInactive)
      px(L0 + 32, 70, 4, 14, ROLE.structure); px(L0 + 88, 70, 4, 14, ROLE.structure)
    })
    sc.item(84, () => { px(L0 + 14, 60, 1, 24, ROLE.inactive); px(L0 + 12, 84, 5, 1, ROLE.inactive); blit(["sssss", ".sss."], L0 + 12, 57, { s: ROLE.body }) })
    sc.item(150, () => { px(L0 + 22, 140, 18, 10, ROLE.attention); px(L0 + 24, 138, 14, 3, tint(ROLE.attention, ROLE.ground, 0.7)) })
    sc.item(156, () => {
      px(W - 14, 100, 14, 56, ROLE.structure); px(W - 14, 100, 14, 2, ROLE.borderInactive)
      blit(COOLER, W - 12, 98, { k: ROLE.key, m: ROLE.prose, a: ROLE.alarm, o: ROLE.inactive })
      blit(COFFEE, W - 11, 128, { m: ROLE.inactive, l: ROLE.live, c: ROLE.prose })
      if (using("coffee")) blit(f % 2 ? ["v.v", ".v."] : [".v.", "v.v"], W - 9, 125, { v: ROLE.prose })
      px(W - 13, 140, 12, 15, ROLE.prose); px(W - 3, 145, 1, 4, ROLE.inactive) // the fridge
    })
    sc.item(186, () => blit(BIG_PLANT, L0 + 4, 175, { l: ROLE.live, o: ROLE.structure }))

    // ── people, Nina ──
    const queued = [...this.actors.values()].filter((x) => x.spot.kind === "queue")
    drawActors(sc, this.actors.values(), this.talk, a, focus)
    if (queued.length > this.plan.queue.length) sc.overhead.push(() => text(`+${queued.length - this.plan.queue.length + 1}`, 94, 176, ROLE.attention))
    const c = this.cat
    drawCat(sc, c, (c.x === CAT_DESK.x || c.x === PERCH_TOP.x) && c.y < 100 ? 104 : null)
    this.drawDog(sc)
    this.drawAntics(sc)

    if (!a.ok || (a.roster.length === 0 && a.bench.length === 0)) text(a.ok ? "nobody on the clock" : (a.note ?? "channel down"), (F0 + F1) / 2, 120, a.ok ? ROLE.inactive : ROLE.alarm)
    return sc.finish()
  }

  /**
   * Nina and Argos, when both are on the floor of the same room (your office, or the lounge) and
   * neither is on the way somewhere: now and then he sneaks up on her, she bats him awake, they
   * chase round the room, or it all ends in a scuffle. The cat keeps to straight runs inside the
   * room's open floor; the dog walks the people's routes or follows her trail.
   */
  private stepAntics(): boolean {
    const c = this.cat, d = this.dog, now = this.tick
    // a pair of lines is an exchange: the second waits for the first, or their balloons collide
    const shout = (who: "cat" | "dog", text: string, reply = false) => (who === "cat" ? this.catSay(text, 25, reply ? 25 : 0) : this.dogSay(text, reply ? 25 : 0))
    const a = this.antic
    if (a) {
      if (a.kind === "sneak" && !d.path.length) {
        d.creep = false; d.mode = "sit"; d.until = now + 150
        shout("dog", "BOO!"); shout("cat", "How DARE you.", true)
        c.path = [this.catFlee(c)]; c.mode = "walk"; c.until = now + 250
        this.antic = null
      } else if (a.kind === "bap" && !c.path.length) {
        shout("cat", "*bap* Up, peasant."); shout("dog", "!?", true)
        d.mode = "sit"; d.until = now + 120; c.mode = "sit"; c.until = now + 200
        this.antic = null
      } else if (a.kind === "chase") {
        if (!c.path.length) { c.path = [a.lap[0]!]; a.lap.push(a.lap.shift()!) ; c.mode = "walk" }
        a.trail.push({ x: c.x, y: c.y })
        if (a.trail.length > 10) { const p = a.trail.shift()!; d.path = [p]; d.mode = "walk" }
        if (now >= a.until) {
          shout("dog", "woof!")
          c.path = []; c.mode = "sit"; c.until = now + 200
          d.path = []; d.mode = "sit"; d.until = now + 150; d.aisle = d.y
          this.antic = null
        }
      } else if (a.kind === "scuffle" && now >= a.until) {
        c.path = [this.catFlee(c)]; c.mode = "walk"; c.until = now + 250
        d.until = now; d.mode = "sit"; d.aisle = d.y
        shout("cat", "My COLLAR! Do you know what this cost?")
        this.antic = null
      }
      return true
    }
    if (now % 20 || Math.random() > 0.08) return false
    const room = this.petRoom(c), alsoHere = this.petRoom(d)
    if (!room || room !== alsoHere || c.path.length || d.path.length || this.plan.cat.via(c)) return false
    const near = Math.abs(c.x - d.x) + Math.abs(c.y - d.y) < 60, r = Math.random()
    const lap = this.lapOf(room)
    if (d.mode === "sleep" && c.mode !== "sleep") {
      c.path = [{ x: d.x - 8, y: c.y }, { x: d.x - 8, y: d.y }]; c.mode = "walk"; c.until = now + 400
      this.antic = { kind: "bap", until: now + 400, trail: [], lap }
    } else if (c.mode !== "walk" && d.mode !== "sleep" && (!near || r < 0.4)) {
      const side = d.x < c.x ? -8 : 8
      d.path = [{ x: d.x, y: d.aisle }, ...this.plan.route(d.x, d.aisle, { x: c.x + side, y: c.y, aisle: c.y, pose: "stand", face: "left", kind: "roam" })]
      d.aisle = c.y; d.mode = "walk"; d.creep = true; c.until = now + 1000
      this.antic = { kind: "sneak", until: now + 1000, trail: [], lap }
    } else if (near && d.mode !== "sleep" && r < 0.8) {
      c.until = now + 1000; this.antic = { kind: "chase", until: now + 80, trail: [], lap }
    } else if (near && d.mode !== "sleep") {
      c.mode = "sit"; c.until = now + 1000; d.mode = "sit"
      this.antic = { kind: "scuffle", until: now + 30, trail: [], lap }
    }
    return !!this.antic
  }
  /** which room's open floor a pet is on: your office, the lounge, or neither */
  private petRoom(p: Pt): "office" | "lounge" | null {
    if (p.x > 8 && p.x < OFF_W - 12 && p.y > 100 && p.y < 152) return "office"
    if (p.x > this.z.L0 + 12 && p.x < this.width - 24 && p.y > 92 && p.y < 156) return "lounge"
    return null
  }
  /** a lap of a room's open floor, for a chase */
  private lapOf(room: "office" | "lounge"): Pt[] {
    if (room === "office") return [{ x: 18, y: 104 }, { x: 80, y: 104 }, { x: 80, y: 148 }, { x: 18, y: 148 }]
    const x0 = this.z.L0 + 18, x1 = Math.min(this.z.L0 + 100, this.width - 26)
    return [{ x: x0, y: 96 }, { x: x1, y: 96 }, { x: x1, y: 152 }, { x: x0, y: 152 }]
  }
  /** away across the same room from wherever she is */
  private catFlee(c: Pt): Pt {
    const lap = this.lapOf(this.petRoom(c) ?? "office")
    return lap.reduce((far, p) => (Math.abs(p.x - c.x) + Math.abs(p.y - c.y) > Math.abs(far.x - c.x) + Math.abs(far.y - c.y) ? p : far))
  }

  /** Argos, his bed and his bowl */
  private drawDog(sc: Scene) {
    const d = this.dog, bed = this.dogBed(), bowl = this.dogBowl(), f = sc.f
    sc.item(bed.y - 3, () => { sc.px(bed.x - 9, bed.y - 4, 18, 5, tint(ROLE.alarm, ROLE.ground, 0.55)); sc.px(bed.x - 8, bed.y - 3, 16, 3, tint(ROLE.alarm, ROLE.prose, 0.35)) })
    sc.item(bowl.y - 2, () => { sc.px(bowl.x - 3, bowl.y - 2, 6, 2, ROLE.inactive); sc.px(bowl.x - 2, bowl.y - 3, 4, 1, ROLE.key) })
    const belly = sc.tick < d.belly
    const frames = belly ? DOG.belly : DOG[d.mode]
    // walking, his legs; sitting, his tail — wagging double time when he's pleased; asleep, breathing
    const rows0 = frames[belly ? f % 2 : d.mode === "walk" ? Math.floor(sc.tick / 2) % 2 : d.mode === "sit" ? (sc.tick < d.woof ? sc.tick % 2 : Math.floor(f / 2) % 2) : f % 4 < 2 ? 0 : 1]!
    const rows = d.face < 0 ? rows0.map((r) => [...r].reverse().join("")) : rows0
    const w = rows[0]!.length, h = rows.length, x = d.x - Math.floor(w / 2), y = d.y - h
    sc.item(d.y, () => {
      const rim = tint(ROLE.prose, ROLE.ground, 0.55), r = { k: rim, e: rim, t: rim, n: rim, i: rim, p: rim, c: rim }
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, -1]] as const) sc.blit(rows, x + dx, y + dy, r)
      sc.blit(rows, x, y, { k: ROLE.body, t: ROLE.body, e: tint(ROLE.body, ROLE.structure, 0.4), n: ROLE.fieldInk, i: ROLE.fieldInk, c: ROLE.fieldInk, p: ROLE.attention })
      if (d.mode === "sleep" && !belly && f % 6 < 3) sc.text("z", x + w + 1, y - 1, ROLE.inactive, 10)
      if (d.creep && f % 4 < 2) sc.text("...", d.x, y - 2, ROLE.inactive, 9)
      if (d.fuss) drawFuss(sc, d.fuss, { x, y, w, h })
      sc.hits.push({ x: x - 1, y: y - 2, w: w + 2, h: h + 3, tip: `${DOG_NAME} - click to pat him`, act: { kind: "dog" } })
    })
    if (d.said && sc.tick >= d.saidFrom && sc.tick < d.saidUntil) sc.balloons.push({ t: "balloon", lines: balloonLines(d.said), cx: d.x, top: y })
  }

  /** the dust cloud of a scuffle */
  private drawAntics(sc: Scene) {
    const c = this.cat, d = this.dog, f = sc.f
    if (this.antic?.kind !== "scuffle") return
    const mx = Math.round((c.x + d.x) / 2), my = Math.round((c.y + d.y) / 2) - 4
    sc.item(Math.max(c.y, d.y) + 1, () => {
      for (let i = 0; i < 9; i++) { const a = i * 0.7 + f * 0.9, r = 4 + ((i + f) % 3); sc.px(mx + Math.round(Math.cos(a) * r * 1.6) - 2, my + Math.round(Math.sin(a) * r) - 2, 4, 4, tint(ROLE.prose, ROLE.ground, 0.6)) }
      sc.px(mx - 6, my - 3, 12, 6, tint(ROLE.prose, ROLE.ground, 0.75))
    })
    sc.overhead.push(() => sc.text(["!#@%", "%@!#", "#!%@"][f % 3]!, mx, my - 9, ROLE.alarm, 11))
  }

  /** the wall calendar: this month, today ringed, a day with something scheduled lit (a dot under it) */
  private calendar(sc: Scene, x0: number, now: Date, booked: number[]) {
    const px = sc.px.bind(sc)
    px(x0, 3, 52, 38, ROLE.structure); px(x0 + 1, 4, 50, 36, ROLE.prose); px(x0 + 1, 4, 50, 7, ROLE.alarm)
    px(x0 + 12, 2, 2, 3, ROLE.inactive); px(x0 + 38, 2, 2, 3, ROLE.inactive)
    sc.text(now.toLocaleString("en", { month: "short" }).toUpperCase(), x0 + 26, 10, ROLE.prose, 9)
    const first = new Date(now.getFullYear(), now.getMonth(), 1).getDay(), days = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate()
    for (let d = 1; d <= days; d++) {
      const i = first + d - 1, x = x0 + 3 + (i % 7) * 7, y = 13 + Math.floor(i / 7) * 5
      const on = booked.includes(d)
      px(x, y, 6, 4, d === now.getDate() ? ROLE.attention : on ? ROLE.key : d < now.getDate() ? tint(ROLE.prose, ROLE.ground, 0.75) : ROLE.raised)
      if (on) px(x + 2, y + 3, 2, 1, ROLE.edge)
    }
    const ahead = booked.filter((d) => d >= now.getDate()).length
    sc.hits.push({ x: x0, y: 3, w: 52, h: 38, tip: `${now.toDateString()} — the calendar${ahead ? `: something scheduled on ${ahead} day(s) still to come` : ""}`, act: { kind: "calendar" } })
  }

  /** the whiteboard: the worklines by stage, each one a readable line in its coworker's colour */
  private whiteboard(sc: Scene, a: Agents, measure: Measure, x0: number, x1: number) {
    const { px } = { px: sc.px.bind(sc) }
    px(x0 - 1, 2, x1 - x0 + 2, 39, ROLE.structure); px(x0, 3, x1 - x0, 36, ROLE.ground); px(x0, 39, x1 - x0, 2, ROLE.borderInactive)
    const cols = boardColumns(a), colW = (x1 - x0) / cols.length
    cols.forEach((col, c) => {
      const cx = x0 + c * colW
      if (c) px(Math.round(cx), 4, 1, 34, ROLE.edge)
      const lh = measure.lineHeight?.(9) ?? 6
      const head = `${COLS[c]} ${col.items.length}`
      sc.text(head, cx + 3, 3 + lh - 0.5, ROLE.key, measure(head, 10) <= colW - 4 ? 10 : 9, "left")
      sc.hits.push({ x: cx, y: 3, w: colW, h: lh + 1, tip: `${COLS[c]!.toLowerCase()}: open as a list`, act: { kind: "column", col: c } })
      // as many lines as fit at the surface's text size; the rest are a "+n more" (and the column's list)
      const room = Math.max(1, Math.floor((38 - 3 - lh) / lh)), shown = col.items.slice(0, col.items.length > room ? room - 1 : room)
      shown.forEach((it, i) => {
        const y = 3 + lh * (i + 2)
        const id = it.act.kind === "ticket" ? it.act.id : it.act.kind === "thread" ? it.act.tid : 0
        const colour = it.asks ? (sc.f % 2 ? ROLE.attention : ROLE.prose) : it.act.kind === "ticket" ? (it.routed ? ROLE.meta : ROLE.prose) : it.who ? shirtOf(it.archetype) : ROLE.inactive
        px(cx + 3, y - 3, 2, 2, colour)
        sc.text(fit(measure, `#${id} ${it.title}`, colW - 9, 9), cx + 7, y, colour, 9, "left")
        sc.hits.push({ x: cx + 1, y: y - lh + 1, w: colW - 2, h: lh, tip: `#${id} ${it.title}\n${it.stage}${it.who ? ` · ${it.who}` : ""}${it.asks ? "\nwaiting on you" : ""}`, act: it.act })
      })
      if (col.items.length > shown.length) sc.text(`+${col.items.length - shown.length} more`, cx + 7, 3 + lh * (shown.length + 2), ROLE.inactive, 9, "left")
    })
    // the pen in its tray: a new ticket
    sc.blit(["kk.aa.ll"], x1 - 12, 39, { k: ROLE.key, a: ROLE.alarm, l: ROLE.live })
    sc.hits.push({ x: x1 - 14, y: 38, w: 12, h: 4, tip: "new ticket", act: { kind: "pen" } })
  }

  /** the corkboard: the notes left for each other, a squiggle each in its author's colour */
  private corkboard(sc: Scene, a: Agents, x0: number) {
    sc.px(x0, 5, 52, 34, ROLE.structure); sc.px(x0 + 1, 6, 50, 32, tint(ROLE.borderInactive, ROLE.body, 0.25))
    sc.text(`NOTES ${a.notes.length}`, x0 + 26, 12, ROLE.fieldInk, 9)
    a.notes.slice(0, 8).forEach((n, i) => {
      const x = x0 + 3 + (i % 4) * 12, y = 16 + Math.floor(i / 4) * 10
      const who = a.bench.find((b) => b.name === n.author)
      sc.px(x, y, 11, 8, ROLE.prose); sc.px(x + 5, y, 1, 1, ROLE.alarm)
      sc.blit(SCRIBBLES[n.id % SCRIBBLES.length]!, x + 1, y + 3, { k: who ? shirtOf(who.archetype) : ROLE.inactive })
      sc.hits.push({ x, y, w: 11, h: 8, tip: `${n.author}: ${n.body}`, act: { kind: "notes" } })
    })
    sc.hits.push({ x: x0, y: 5, w: 52, h: 34, tip: `${a.notes.length} note(s): open as a list`, act: { kind: "notes" } })
  }

  /** windows on the sky as it is outside: night with its stars, dawn and dusk, day */
  private windows(sc: Scene, x0: number, x1: number, now: Date) {
    const h = now.getHours() + now.getMinutes() / 60
    const sky = h < 6 || h >= 20.5 ? "night" : h < 7.5 || h >= 18.5 ? "dusk" : "day"
    for (let x = x0; x + 30 <= x1; x += 36) {
      sc.px(x, 6, 30, 30, ROLE.inactive)
      if (sky === "night") {
        sc.px(x + 1, 7, 28, 28, ROLE.ground)
        for (let i = 0; i < 5; i++) sc.px(x + 3 + ((i * 11 + x) % 24), 9 + ((i * 7) % 20), 1, 1, ROLE.prose)
      } else if (sky === "dusk") {
        sc.px(x + 1, 7, 28, 10, tint(ROLE.assistant, ROLE.ground, 0.6)); sc.px(x + 1, 17, 28, 10, ROLE.attention); sc.px(x + 1, 27, 28, 8, ROLE.body)
      } else {
        sc.px(x + 1, 7, 28, 28, tint(ROLE.key, ROLE.prose, 0.3))
        sc.px(x + 5 + ((x >> 3) % 12), 12, 8, 2, ROLE.prose); sc.px(x + 7 + ((x >> 3) % 12), 11, 4, 1, ROLE.prose)
      }
      sc.px(x + 14, 6, 2, 30, ROLE.inactive); sc.px(x, 20, 30, 1, ROLE.inactive)
      sc.px(x - 1, 36, 32, 2, ROLE.structure)
    }
  }

  /** the TV on the lounge's wall, showing the desktop's ambient shows in turn; a click changes the channel */
  private tv(sc: Scene, x0: number) {
    sc.px(x0, 6, 52, 32, ROLE.inactive); sc.px(x0 + 2, 8, 48, 28, ROLE.ground)
    const { dots, w } = this.tvSet.screen
    for (let i = 0; i < dots.length; i++) if (dots[i]) sc.px(x0 + 2 + (i % w), 8 + ((i / w) | 0), 1, 1, hueRole(dots[i]! - 1))
    sc.hits.push({ x: x0, y: 6, w: 52, h: 32, tip: `the TV: ${this.tvSet.channel} — click for the next channel`, act: { kind: "tv" } })
  }

  /** the clock on the wall, telling the real time */
  private clock(sc: Scene, cx: number, now: Date) {
    const cy = 16, r = 8
    for (let dy = -r; dy <= r; dy++) { const half = Math.round(Math.sqrt(r * r - dy * dy)); sc.px(cx - half, cy + dy, half * 2 + 1, 1, Math.abs(dy) === r || half <= 1 ? ROLE.structure : ROLE.prose) }
    const hand = (turns: number, len: number, c: string) => { for (let i = 1; i <= len; i++) sc.px(Math.round(cx + Math.sin(turns * 2 * Math.PI) * i), Math.round(cy - Math.cos(turns * 2 * Math.PI) * i), 1, 1, c) }
    hand((now.getHours() % 12 + now.getMinutes() / 60) / 12, 4, ROLE.fieldInk)
    hand(now.getMinutes() / 60, 6, ROLE.structure)
    sc.text(`${String(now.getHours()).padStart(2, "0")}:${String(now.getMinutes()).padStart(2, "0")}`, cx, 36, ROLE.prose, 14)
  }

  /** the in-tray on its side table: a sheet for each thing you haven't read (six at most), the top one lit */
  private inTray(sc: Scene, unread: number) {
    const { x, y } = TRAY, px = sc.px.bind(sc)
    sc.item(y + 14, () => {
      px(x, y + 6, 16, 2, ROLE.structure); px(x + 1, y + 8, 2, 6, ROLE.structure); px(x + 13, y + 8, 2, 6, ROLE.structure)
      px(x + 2, y + 2, 12, 4, ROLE.inactive); px(x + 3, y + 3, 10, 3, ROLE.edge)
      const sheets = Math.min(6, unread)
      for (let i = 0; i < sheets; i++) px(x + 3 + (i % 2), y + 4 - i, 10, 1, i === sheets - 1 ? ROLE.attention : ROLE.prose)
      if (unread) sc.text(`${unread} new`, x + 8, y - 4, ROLE.attention, 9)
    })
    sc.hits.push({ x, y: y - 6, w: 16, h: 20, tip: `the in-tray: what just happened${unread ? ` — ${unread} new` : ""}`, act: { kind: "tray" } })
  }

  /** the beacon over your door: dark while nothing is stuck, turning red while something is */
  private beacon(sc: Scene, stuck: number) {
    const x = OFF_W - 4, y = OFF_DOOR - 16, f = sc.f, px = sc.px.bind(sc)
    sc.item(BAND + 1, () => {
      px(x, y + 5, 9, 2, ROLE.inactive)
      const on = stuck > 0 && f % 4 < 2
      px(x + 1, y, 7, 5, stuck ? (on ? ROLE.alarm : tint(ROLE.alarm, ROLE.ground, 0.5)) : ROLE.raised)
      px(x + 3, y + 1, 3, 1, stuck ? ROLE.prose : ROLE.inactive)
      if (on) for (const [dx, dy] of [[-3, 1], [10, 1], [-2, -2], [9, -2]] as const) px(x + dx, y + dy, 2, 1, ROLE.alarm)
    })
    if (stuck) sc.overhead.push(() => sc.text(`${stuck} stuck`, x + 4, y - 4, ROLE.alarm, 9))
    sc.hits.push({ x: x - 3, y: y - 8, w: 15, h: 15, tip: stuck ? `the beacon: ${stuck} stuck — blockers, failed checks, threads nobody leads` : "the beacon: nothing is stuck", act: { kind: "beacon" } })
  }

  /** the server rack: its lights blink green while the service is well, red while it needs a look */
  private rack(sc: Scene, a: Agents, x: number) {
    const f = sc.f, px = sc.px.bind(sc), warn = a.health?.state === "warn"
    sc.item(174, () => {
      px(x, 146, 12, 28, ROLE.structure); px(x + 1, 147, 10, 26, ROLE.edge)
      for (let u = 0; u < 6; u++) {
        const y = 149 + u * 4
        px(x + 2, y, 8, 3, ROLE.inactive)
        const lit = (u * 7 + f) % 5 !== 0
        px(x + 3, y + 1, 1, 1, warn && u < 2 ? (f % 2 ? ROLE.alarm : ROLE.raised) : lit ? ROLE.live : ROLE.raised)
        px(x + 5, y + 1, 1, 1, (u + f) % 3 ? ROLE.key : ROLE.raised)
      }
    })
    const tip = !a.health ? "the server rack" : warn ? `the server rack: needs a look — ${a.health.problems.join("; ")}` : "the server rack: all green"
    sc.hits.push({ x, y: 146, w: 12, h: 28, tip, act: { kind: "rack" } })
  }

  /** Nina's corner: the tower by the glass, the litter box, the yarn (rolling while she bats it), a mouse */
  private ninasCorner(sc: Scene) {
    const c = this.cat, px = sc.px.bind(sc)
    sc.item(88, () => {
      const tx = TOWER_X, carpet = ROLE.meta, under = tint(ROLE.meta, ROLE.ground, 0.5)
      px(tx + 4, 54, 3, 32, ROLE.inactive); for (let y = 56; y < 84; y += 3) px(tx + 4, y, 3, 1, ROLE.borderInactive)
      px(tx, 84, 11, 3, carpet); px(tx, 87, 11, 1, under)
      px(tx, 69, 11, 2, carpet); px(tx, 71, 11, 1, under)
      px(tx - 1, 52, 12, 2, carpet); px(tx - 1, 54, 12, 1, under)
      px(tx + 10, 71, 1, 5, ROLE.prose); px(tx + 9, 76, 3, 2, ROLE.attention)
    })
    sc.item(92, () => { px(1, 93, 10, 4, ROLE.key); px(2, 94, 8, 2, ROLE.inactive) })
    sc.item(100, () => px(1, 97, 10, 2, ROLE.key))
    sc.item(YARN.y, () => {
      const yx = YARN.x + (c.mode === "play" ? [0, 1, 2, 1][c.yarn]! : 0)
      px(yx, YARN.y - 3, 3, 3, ROLE.attention); px(yx + 1, YARN.y - 2, 1, 1, ROLE.assistant); px(yx - 2, YARN.y - 1, 2, 1, ROLE.attention)
    })
    sc.item(MOUSE.y, () => { px(MOUSE.x, MOUSE.y - 2, 4, 2, ROLE.prose); px(MOUSE.x + 3, MOUSE.y - 3, 1, 1, ROLE.attention); px(MOUSE.x - 2, MOUSE.y - 1, 2, 1, ROLE.attention) })
  }

  /**
   * A table of four across the floor: a monitor at every seat facing its chair (lit while its owner
   * works, pink while their thread waits on you), the owner's things beside it, their nameplate below.
   */
  private table(sc: Scene, a: Agents, measure: Measure, ty: number, mine: Chair[], focus: Focus) {
    const { F0 } = this.z, x0 = F0 + 14, w = SEATS * SEAT_GAP + 4, f = sc.f
    const stateOf = (c: Chair) => {
      const owner = c.agent ? this.actors.get(c.agent) : undefined
      return { owner, p: owner?.seat, seated: !!owner && owner.spot.kind === "desk" && !owner.path.length, asks: !!owner && needsYou(a.threads.find((t) => t.id === owner.seat.thread_id)) }
    }
    sc.item(ty + 22, () => {
      sc.px(x0, ty + 12, w, 2, ROLE.structure)
      sc.px(x0 + 1, ty + 14, w - 2, 8, ROLE.borderInactive)
      for (const c of mine) {
        const { owner, seated, asks } = stateOf(c)
        const mx = c.x - 5, my = ty + 3
        sc.px(mx, my, 10, 7, ROLE.inactive); sc.px(mx + 4, my + 7, 2, 2, ROLE.inactive)
        if (asks) sc.px(mx + 1, my + 1, 8, 5, f % 2 ? ROLE.attention : ROLE.raised)
        else {
          sc.px(mx + 1, my + 1, 8, 5, ROLE.ground)
          if (seated) for (let l = 0; l < 3; l++) sc.px(mx + 2, my + 1 + l * 2, 1 + ((f + l * 3 + c.x) % 6), 1, ROLE.live)
        }
        if (owner) decor(sc, owner.look, c.x + 11, ty + 12)
      }
    })
    sc.item(ty + 30, () => {
      for (const c of mine) {
        if (!c.agent) continue
        const { owner, p, seated, asks } = stateOf(c)
        // a nameplate where three letters fit at the surface's text size; the crew card and the tip have every name
        if (measure(c.agent.slice(0, 3), 11) <= SEAT_GAP) sc.text(fit(measure, c.agent, SEAT_GAP - 1, 11), c.x, ty + 37, asks ? ROLE.attention : seated ? shirtOf(p?.archetype) : ROLE.inactive, 11)
        // their monitor: a door into their terminal
        if (p && p.thread_id > 0) sc.hits.push({ x: c.x - 5, y: ty + 3, w: 10, h: 9, tip: `${c.agent}'s terminal — click to look over their shoulder`, act: { kind: "terminal", tid: p.thread_id } })
        const hx = c.x - 10, hy = ty, hw = SEAT_GAP, hh = 39
        const where = !owner ? "" : seated ? "working" : owner.spot.kind === "queue" ? "in your queue" : owner.leaving ? "leaving" : owner.path.length ? "walking" : owner.spot.kind === "laptop" ? "on call, at a laptop in the meeting room" : `idle, at the ${owner.spot.kind}`
        const agentId = a.bench.find((b) => b.name === c.agent)?.agent_id ?? null
        sc.hits.push({ x: hx, y: hy, w: hw, h: hh, tip: p ? tipOf(p, a.threads.find((t) => t.id === p.thread_id), where) : c.agent, act: { kind: "person", agentId, name: c.agent, tid: p && p.thread_id > 0 ? p.thread_id : null } })
        if (p && p.thread_id > 0 && p.thread_id === focus.picked) sc.ink.push({ t: "brackets", x: hx, y: hy, w: hw, h: hh, color: ROLE.body })
      }
    })
  }
}
