// The wide room: the office as the TUI draws it, as wide as the terminal. Under one long back wall —
// the whiteboard with its titles readable, the notes corkboard, windows on the real sky, a clock, the
// TV — four zones side by side: your office (Nina's corner too), the open floor (the manager's and
// the lead's desks, the crew board, two tables of four), a glass meeting room, the lounge with its
// kitchen. A hallway runs along the bottom; every zone has one lane down to it, and every walk goes
// lane → hallway → lane, so nobody needs a path finder and nobody walks through a desk.
import { balloonLines, fit, type Frame, type Measure } from "../kit/canvas"
import { boardColumns, COLS, isManager, needsYou, peopleOf, tipOf } from "../kit/crew"
import { drawActors, drawCat, drawFuss, drawParty, Scene, type Focus } from "../kit/draw"
import { bossDesk, crewBoard, decor, execDesk } from "../kit/furniture"
import { ROLE, tint } from "../kit/palette"
import { FUSS, Sim, keyOf, type Actor, type Fussing, type Plan, type Pt, type Spot } from "../kit/sim"
import { NINA, pick, type Fuss } from "../kit/voices"
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
  return { L0, M0, MW, Mc: M0 + MW / 2, F0, F1, W: w }
}
type Zones = ReturnType<typeof zones>
/** a zone's lane: the column it walks down to the hallway */
function laneOf(z: Zones, x: number) {
  return x <= OFF_W ? OFF_LANE : x < z.M0 ? z.F0 + 3 : x < z.L0 ? z.Mc : z.L0 + 6
}

/**
 * Where the pastimes are, for a room's zones: the games corner under the meeting room (a ping-pong
 * table left of its lane, two arcade cabinets right of it) and the aquarium on the open floor past
 * the second table — what the plan routes to and the render draws, from one place.
 */
function corner(z: Zones) {
  return {
    table: { x: z.M0 + 8, y: 146, w: 26, h: 12 },
    cabinets: [z.Mc + 8, z.Mc + 24].map((x) => ({ x, y: 128, w: 12, h: 20 })),
    tank: { x: z.F0 + 136, y: 100, w: 30, h: 24 },
    // the lounge: the snack machine and a bookshelf against its back wall, an armchair by the shelf;
    // a foosball table and a pool table down by the hallway
    vending: { x: z.L0 + 18, y: 46, w: 12, h: 24 },
    shelf: { x: z.L0 + 96, y: 46, w: 22, h: 20 },
    foos: { x: z.L0 + 30, y: 166, w: 26, h: 12 },
    // clear of the foosball's right-hand player, and of the EXIT sign's label over the room's last 26 px
    pool: { x: z.L0 + 68, y: 166, w: 26, h: 12 },
  }
}

/** where Nina sits to watch the fish: on the floor in front of the aquarium */
function fishWatch(z: Zones): Pt { const t = corner(z).tank; return { x: t.x + 15, y: t.y + t.h + 8 } }

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
// a radiator on your office's left wall; on a cold day Nina sits on top of it
const RADIATOR = { x: 2, y: 116, w: 10, h: 12 }, CAT_WARM = { x: 7, y: 115 }
// your in-tray, on a side table left of your desk
const TRAY = { x: 4, y: 62 }

/** the plan, and the furniture's footprints (for the route test): every rectangle no feet may enter */
export function widePlan(w: number): Plan<Layout> & { blocks: (l: Layout) => { x: number; y: number; w: number; h: number }[] } {
  const z = zones(w)
  const { L0, M0, MW, Mc, F0, F1 } = z
  const inOffice = (x: number) => x <= OFF_W
  const { table, cabinets, tank, vending, shelf, foos, pool } = corner(z)
  const at = (x: number, y: number, aisle: number, face: Spot["face"], kind: Spot["kind"], partner?: Pt): Spot => ({ x, y, aisle, pose: "stand", face, kind, ...(partner ? { with: partner } : {}) })
  const ends = [{ x: table.x - 4, y: table.y + 6 }, { x: table.x + table.w + 4, y: table.y + 6 }]
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
      // the pastimes: a game at a cabinet, a rally across the table, the fish, the sky through the
      // meeting room's windows, the plants, a chat, a pet
      ...cabinets.map((c) => at(c.x + 6, c.y + c.h + 10, c.y + c.h + 10, "up", "arcade")),
      at(ends[0]!.x, ends[0]!.y, table.y + table.h + 12, "right", "pingpong", ends[1]),
      at(ends[1]!.x, ends[1]!.y, table.y + table.h + 12, "left", "pingpong", ends[0]),
      at(tank.x + 8, tank.y + tank.h + 10, tank.y + tank.h + 10, "up", "aquarium"),
      at(tank.x + 22, tank.y + tank.h + 10, tank.y + tank.h + 10, "up", "aquarium"),
      at(Mc - 32, 54, 116, "up", "window"), at(Mc + 32, 54, 116, "up", "window"),
      at(L0 + 22, 184, 184, "left", "plant"), at(18, 168, 168, "left", "plant"),
      at(L0 + 52, 124, 124, "right", "chat", { x: L0 + 66, y: 124 }), at(L0 + 66, 124, 124, "left", "chat", { x: L0 + 52, y: 124 }),
      at(L0 + 90, 118, 118, "right", "pet"), at(L0 + 40, 106, 106, "right", "pet"),
      at(vending.x + 6, 80, 94, "up", "vending"),
      at(foos.x - 4, foos.y + 6, 184, "right", "foosball", { x: foos.x + foos.w + 4, y: foos.y + 6 }),
      at(foos.x + foos.w + 4, foos.y + 6, 184, "left", "foosball", { x: foos.x - 4, y: foos.y + 6 }),
      // pool: a player at each end of the table's far side, so the table, drawn after, never hides the game
      at(pool.x + 3, pool.y - 4, pool.y - 4, "down", "pool", { x: pool.x + 23, y: pool.y - 4 }),
      at(pool.x + 23, pool.y - 4, pool.y - 4, "down", "pool", { x: pool.x + 3, y: pool.y - 4 }),
      { x: shelf.x + 8, y: 84, aisle: 94, pose: "sit", face: "down", kind: "read" },
    ],
    // the meeting room's table, two laptops a side: where the warm but unbusy sit, on call
    oncall: [Mc - 22, Mc + 22].flatMap((x) => [81, 95].map((y): Spot => ({ x, y, aisle: 116, pose: "sit", face: x < Mc ? "right" : "left", kind: "laptop" }))),
    exit: { x: w - 3, y: HALL, aisle: HALL, pose: "stand", face: "right", kind: "exit" },
    pen: { x: F1 - 30, y: 51, aisle: 51, pose: "stand", face: "up", kind: "note" },
    // under the suggestion box on the wall between the notes board and the windows
    box: { x: F1 + 1, y: 51, aisle: 51, pose: "stand", face: "up", kind: "note" },
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
      nap: CAT_NAP, desk: CAT_DESK, play: PLAY, litter: LITTER, perches: [PERCH_TOP, PERCH_MID], warm: CAT_WARM,
      // the zoomies: your office (your desk, her tower) and the lounge (the couch back, the top of
      // the TV, the kitchen counter), each first the floor spot she lands on after
      leaps: [
        [CAT_NAP, CAT_DESK, PERCH_TOP, PERCH_MID, { x: 18, y: 112 }, { x: 72, y: 142 }],
        [{ x: L0 + 52, y: 104 }, { x: L0 + 46, y: 69 }, { x: L0 + 80, y: 69 }, { x: L0 + 58, y: 7 }, { x: w - 7, y: 99 }, { x: L0 + 100, y: 140 }],
      ],
      // the armchair too, when it's empty: a princess takes the good seat
      lounge: [{ x: L0 + 52, y: 104 }, { x: w - 40, y: 126 }, { x: shelf.x + 8, y: 82 }],
      spots: [CAT_NAP, { x: 24, y: 140 }, { x: 40, y: 104 }, CAT_DESK, PERCH_TOP, PERCH_MID, PLAY, { x: L0 + 52, y: 104 }, fishWatch(z)],
      via: (p: Pt) =>
        p.x === CAT_DESK.x && p.y === CAT_DESK.y ? { x: CAT_DESK.x, y: 100 }
          : p.x === PERCH_TOP.x && p.y <= PERCH_MID.y ? { x: PERCH_TOP.x, y: 94 }
            : p.x === LITTER.x && p.y === LITTER.y ? { x: LITTER.x, y: 106 }
              : p.x === CAT_WARM.x && p.y === CAT_WARM.y ? { x: CAT_WARM.x, y: 136 } : null,
      // out through your office's door and along the hallway, when she changes rooms
      // out of one room and into another along the hallway: your office by its door, the lounge by
      // its lane, the open floor by the column she watches the fish from
      door: (from, to) => {
        const roomOf = (p: Pt) => (inOffice(p.x) ? "office" : p.x >= L0 ? "lounge" : "floor")
        const a = roomOf(from), b = roomOf(to), fx = fishWatch(z).x
        if (a === b) return []
        const out = { office: [{ x: OFF_LANE, y: 160 }, { x: OFF_LANE, y: HALL - 3 }], lounge: [{ x: L0 + 6, y: HALL - 3 }], floor: [{ x: fx, y: HALL - 3 }] }
        const into = { office: [{ x: OFF_LANE, y: HALL - 3 }, { x: OFF_LANE, y: 160 }], lounge: [{ x: L0 + 6, y: HALL - 3 }, { x: L0 + 6, y: to.y }], floor: [{ x: fx, y: HALL - 3 }] }
        return [...out[a], ...into[b]]
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
        RADIATOR,
        table, ...cabinets, tank, vending, shelf, foos, pool, // the pastimes' furniture
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
  shipped: ["{name} SHIPPED IT! Sing, O Muse!", "A homecoming worthy of Odysseus, {name}!"],
  rally: ["BALL. Ball ball ball. BALL.", "Left! Right! Left! I can't take it!"],
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
  /** each cabinet's best score and who set it; the game each player is on; a new best's fanfare until `fanfare` */
  private highs: ({ name: string; score: number } | null)[] = [null, null]
  private runs = new Map<string, { cab: number; score: number }>()
  private fanfare = 0
  /** how much each plant has been watered, by the x of its waterer's spot: enough and it flowers */
  private watered = new Map<number, number>()
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
    if ((what === "test" || what === "done" || what === "queue" || what === "shipped") && this.quiet(this.dog.saidUntil) && Math.random() < (what === "shipped" ? 0.7 : 0.3)) this.dogSay(this.argos(what, actor.seat.agent), what === "shipped" ? 20 : 0)
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
    if (d.mode !== "sleep" && !d.fuss && this.quiet(d.saidUntil) && Math.random() < 0.0015) {
      const near = [...this.actors.values()].find((a) => !a.moving && !a.path.length && (a.spot.kind === "couch" || a.spot.kind === "cooler" || a.spot.kind === "coffee" || a.spot.kind === "roam") && Math.abs(a.x - d.x) < 22 && Math.abs(a.y - d.y) < 16)
      if (near) { this.fussDog(near); return true }
    }
    if (this.tick < d.until) return d.mode === "sit" && this.tick % 3 === 0
    const r = Math.random(), working = [...this.actors.values()].filter((a) => a.spot.kind === "desk" && !a.moving && !a.path.length)
    const host = working.length && r < 0.35 ? pick(working) : null
    const spot = (x: number, y: number, aisle = y): Spot => ({ x, y, aisle, pose: "stand", face: "left", kind: "roam" })
    const { table: t } = corner(this.z)
    const watch = !host && this.at("pingpong").length === 2 && r > 0.85
    const goal: Spot = host ? this.plan.visit(host)
      : watch ? { x: t.x + t.w / 2, y: t.y + t.h + 6, aisle: t.y + t.h + 12, pose: "stand", face: "left", kind: "roam" }
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
    for (const x of this.at("plant")) this.watered.set(x.spot.x, (this.watered.get(x.spot.x) ?? 0) + 1)
    this.arcadeScores()
    // Nina at the aquarium paws at the glass, and has thoughts about the fish
    const c = this.cat, fw = fishWatch(this.z)
    if (c.x === fw.x && c.y === fw.y && !c.path.length) {
      if (c.mode === "sit") c.mode = "play"
      if (this.quiet(c.saidUntil) && Math.random() < 0.006) this.catSay(this.line("Nina", "fish", NINA.fish))
    }
    // at the ping-pong table for a rally, his head goes with the ball, and now and then he has to say so
    const { table: t } = corner(this.z), d = this.dog, rally = this.at("pingpong").length === 2
    if (rally && !d.path.length && Math.abs(d.x - (t.x + t.w / 2)) < 3 && Math.abs(d.y - (t.y + t.h + 6)) < 3) {
      d.face = this.tick % 16 < 8 ? 1 : -1
      if (this.quiet(d.saidUntil) && Math.random() < 0.01) this.dogSay(this.argos("rally"))
    }
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
    this.drawBox(sc, F1 - 4)
    this.windows(sc, M0 + 4, L0 + 30, now, a.weather ?? null)
    this.season(sc, now)
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
    this.pastimes(sc)

    // ── people, Nina ──
    const queued = [...this.actors.values()].filter((x) => x.spot.kind === "queue")
    drawActors(sc, this.actors.values(), this.talk, a, focus)
    if (queued.length > this.plan.queue.length) sc.overhead.push(() => text(`+${queued.length - this.plan.queue.length + 1}`, 94, 176, ROLE.attention))
    const c = this.cat
    const chair = corner(this.z).shelf.x + 8
    drawCat(sc, c, (c.x === CAT_DESK.x || c.x === PERCH_TOP.x) && c.y < 100 ? 104 : c.x === chair && c.y === 82 ? 84 : c.x === CAT_WARM.x && c.y === CAT_WARM.y ? RADIATOR.y + RADIATOR.h + 1 : null)
    // the radiator, and on a cold day the heat shimmering off it
    sc.item(RADIATOR.y + RADIATOR.h, () => {
      px(RADIATOR.x, RADIATOR.y, RADIATOR.w, RADIATOR.h, ROLE.prose)
      for (let k = 1; k < RADIATOR.w; k += 2) px(RADIATOR.x + k, RADIATOR.y + 1, 1, RADIATOR.h - 2, tint(ROLE.prose, ROLE.ground, 0.6))
      if ((a.weather?.temp_c ?? 20) < 10) for (let k = 0; k < 3; k++) px(RADIATOR.x + 2 + k * 3 + ((f + k) % 2), RADIATOR.y - 3 - ((f + k) % 3), 1, 2, tint(ROLE.alarm, ROLE.ground, 0.5))
    })
    this.drawDog(sc)
    this.drawAntics(sc)
    const shipper = this.party && [...this.actors.values()].find((x) => x.seat.agent === this.party!.agent)
    if (shipper) drawParty(sc, shipper.x, shipper.y, this.party!.until - this.tick)

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

  /** the cabinets' best scores, and who holds them */
  highScores() { return this.highs }

  /** whoever plays racks up points; walking away, a best beaten is theirs, with a fanfare */
  private arcadeScores() {
    const { cabinets } = corner(this.z), playing = new Set<string>()
    for (const x of this.at("arcade")) {
      const cab = cabinets.findIndex((c) => Math.abs(c.x + 6 - x.x) < 3)
      if (cab < 0) continue
      playing.add(x.seat.agent)
      const run = this.runs.get(x.seat.agent) ?? { cab, score: 0 }
      if (this.tick % 4 === 0) run.score += 10 * Math.floor(Math.random() * 6)
      this.runs.set(x.seat.agent, run)
    }
    for (const [who, run] of this.runs) {
      if (playing.has(who)) continue
      this.runs.delete(who)
      if (run.score <= (this.highs[run.cab]?.score ?? 0)) continue
      this.highs[run.cab] = { name: who, score: run.score }
      this.fanfare = this.tick + 40
      const x = [...this.actors.values()].find((a) => a.seat.agent === who)
      if (x) { x.emote = "!"; x.emoteUntil = this.tick + 30 }
    }
  }

  /** who is settled at a pastime of `kind`, and where */
  private at(kind: string) { return [...this.actors.values()].filter((x) => x.spot.kind === kind && !x.moving && !x.path.length) }

  /**
   * The games corner and the aquarium. The ping-pong ball flies only when both ends are taken; a
   * cabinet runs its attract screen until someone plays, then a game; the fish come up for flakes
   * when someone at the tank feeds them.
   */
  private pastimes(sc: Scene) {
    const { table: t, cabinets, tank } = corner(this.z), f = sc.f, tick = sc.tick, px = sc.px.bind(sc)
    sc.item(t.y + t.h, () => {
      px(t.x + 2, t.y + 8, 2, 4, ROLE.inactive); px(t.x + t.w - 4, t.y + 8, 2, 4, ROLE.inactive)
      px(t.x, t.y, t.w, 8, tint(ROLE.live, ROLE.ground, 0.4)); px(t.x, t.y, t.w, 1, ROLE.prose); px(t.x, t.y + 7, t.w, 1, ROLE.prose)
      px(t.x + t.w / 2 - 1, t.y - 2, 2, 9, tint(ROLE.prose, ROLE.ground, 0.7))
    })
    const players = this.at("pingpong")
    if (players.length === 2) {
      // a rally: across and back, an arc over the net, a bounce each side
      const p = (tick % 16) / 8, k = p < 1 ? p : 2 - p, x = Math.round(t.x + 2 + k * (t.w - 4)), y = Math.round(t.y + 3 - Math.sin(k * Math.PI) * 7)
      sc.overhead.push(() => px(x, y, 2, 2, ROLE.body))
    }
    cabinets.forEach((c, i) => sc.item(c.y + c.h, () => {
      const body = i ? ROLE.assistant : ROLE.planner, playing = this.at("arcade").some((a) => Math.abs(a.x - (c.x + 6)) < 3)
      // the marquee flickers; a new best sets it flashing
      px(c.x, c.y, c.w, c.h, tint(body, ROLE.ground, 0.55)); px(c.x, c.y, c.w, 3, tick < this.fanfare ? (tick % 2 ? ROLE.attention : ROLE.body) : f % 4 ? body : ROLE.body)
      px(c.x + 2, c.y + 4, 8, 7, ROLE.ground)
      if (playing) {
        // a wave of invaders marching, the ship under them firing
        const dx = Math.floor(f / 2) % 3
        for (let k = 0; k < 3; k++) px(c.x + 2 + dx + k * 2, c.y + 5, 1, 1, ROLE.live)
        px(c.x + 3 + ((f * 3) % 6), c.y + 9, 2, 1, ROLE.key)
        if (f % 2) px(c.x + 4 + ((f * 3) % 6), c.y + 6 + (tick % 3), 1, 1, ROLE.body)
      } else if (f % 6 < 3) px(c.x + 3, c.y + 7, 6, 1, ROLE.body) // insert coin
      px(c.x + 1, c.y + 12, 10, 3, ROLE.edge); px(c.x + 3, c.y + 11, 1, 2, ROLE.prose); px(c.x + 6, c.y + 13, 1, 1, ROLE.alarm); px(c.x + 8, c.y + 13, 1, 1, ROLE.key)
      const best = this.highs[i]
      sc.hits.push({ x: c.x, y: c.y, w: c.w, h: c.h, tip: `the arcade${best ? ` - best ${best.score} by ${best.name}` : ""} - click to play`, act: { kind: "arcade" } })
    }))
    sc.item(tank.y + tank.h, () => {
      const water = tint(ROLE.key, ROLE.ground, 0.35), glass = tint(ROLE.prose, ROLE.ground, 0.6)
      px(tank.x, tank.y + 18, tank.w, 6, ROLE.structure); px(tank.x + 2, tank.y + 23, 2, 1, ROLE.borderInactive)
      px(tank.x, tank.y, tank.w, 18, glass); px(tank.x + 1, tank.y + 2, tank.w - 2, 15, water); px(tank.x, tank.y, tank.w, 1, ROLE.inactive)
      px(tank.x + 1, tank.y + 15, tank.w - 2, 2, tint(ROLE.body, ROLE.ground, 0.5))
      for (const [wx, h] of [[4, 7], [9, 5], [23, 8]] as const) for (let j = 0; j < h; j++) px(tank.x + wx + ((j + f) % 4 === 0 ? 1 : 0), tank.y + 14 - j, 1, 1, ROLE.live)
      const feeding = this.at("aquarium").length > 0 && tick % 300 < 50
      if (feeding) for (let k = 0; k < 4; k++) px(tank.x + 10 + k * 3, tank.y + 3 + ((tick + k * 5) % 10), 1, 1, ROLE.body)
      ;[ROLE.alarm, ROLE.body, ROLE.attention].forEach((col, i) => {
        // each fish swims its own lap; at feeding time they all come up for the flakes
        const lap = 22, s = Math.floor(tick / (2 + i)) + i * 7, p = s % (2 * lap), x = p < lap ? p : 2 * lap - p
        // when Nina is at the glass they gather at her side of it, just out of reach
        const nina = this.cat.x === tank.x + 15 && this.cat.y === tank.y + tank.h + 8 && !this.cat.path.length
        const fx = nina ? tank.x + 10 + i * 3 + Math.round(Math.sin((tick + i * 15) / 7) * 2) : tank.x + 2 + x
        const fy = feeding ? tank.y + 4 + i : nina ? tank.y + 9 + i * 2 : tank.y + 5 + i * 3, right = nina ? i % 2 === 0 : p < lap
        px(fx, fy, 3, 2, col); px(right ? fx - 1 : fx + 3, fy + (f % 2), 1, 1, col)
      })
      for (let k = 0; k < 2; k++) px(tank.x + 6 + k * 14, tank.y + 14 - ((tick + k * 9) % 12), 1, 1, ROLE.prose)
    })
    const { vending: v, shelf, foos, pool } = corner(this.z)
    sc.item(v.y + v.h, () => {
      // the snack machine: rows of snacks behind the glass, a can thunking down when someone buys
      px(v.x, v.y, v.w, v.h, ROLE.alarm); px(v.x + 1, v.y + 2, 7, 16, tint(ROLE.prose, ROLE.ground, 0.3))
      for (let r = 0; r < 4; r++) for (let k = 0; k < 3; k++) px(v.x + 2 + k * 2, v.y + 3 + r * 4, 1, 2, [ROLE.body, ROLE.key, ROLE.live, ROLE.attention][(r + k) % 4]!)
      px(v.x + 9, v.y + 4, 2, 6, ROLE.edge); px(v.x + 9, v.y + 12, 2, 2, f % 2 ? ROLE.live : ROLE.edge)
      px(v.x + 1, v.y + 20, 10, 3, ROLE.edge)
      if (this.at("vending").length && tick % 40 < 8) px(v.x + 4, v.y + 18 + Math.min(3, (tick % 40) >> 1), 2, 2, ROLE.key)
    })
    sc.item(shelf.y + shelf.h, () => {
      // the bookshelf: three shelves of spines
      px(shelf.x, shelf.y, shelf.w, shelf.h, ROLE.structure)
      for (let r = 0; r < 3; r++) for (let k = 0; k < 9; k++) if ((k * 7 + r * 3) % 10 !== 0) px(shelf.x + 2 + k * 2, shelf.y + 2 + r * 6, 1, 5 - ((k + r) % 2), [ROLE.alarm, ROLE.key, ROLE.body, ROLE.live, ROLE.assistant][(k + r * 2) % 5]!)
    })
    // the armchair in front of it, drawn just behind whoever sits in it
    sc.item(83, () => { px(shelf.x + 1, 72, 14, 12, ROLE.planner); px(shelf.x + 3, 74, 10, 8, tint(ROLE.planner, ROLE.ground, 0.6)); px(shelf.x + 1, 84, 2, 2, ROLE.structure); px(shelf.x + 13, 84, 2, 2, ROLE.structure) })
    sc.item(foos.y + foos.h, () => {
      // foosball: the rods slide while a pair plays, the ball rattling between them
      px(foos.x, foos.y, foos.w, foos.h - 4, ROLE.structure); px(foos.x + 2, foos.y + 1, foos.w - 4, 6, tint(ROLE.live, ROLE.ground, 0.45))
      px(foos.x + 3, foos.y + 8, 2, 4, ROLE.structure); px(foos.x + foos.w - 5, foos.y + 8, 2, 4, ROLE.structure)
      const on = this.at("foosball").length === 2
      for (let r = 0; r < 4; r++) {
        const rx = foos.x + 5 + r * 5, dy = on ? ((tick + r * 3) % 4) - 2 : 0
        px(rx, foos.y - 1, 1, 9, ROLE.inactive)
        for (const my of [2, 5]) px(rx, foos.y + my + dy, 1, 1, r % 2 ? ROLE.alarm : ROLE.key)
      }
      if (on) px(foos.x + 3 + ((tick * 3) % (foos.w - 6)), foos.y + 3 + (tick % 2), 1, 1, ROLE.prose)
    })
    sc.item(pool.y + pool.h, () => {
      // the pool table: wood rails, green felt, six pockets; racked and waiting, or a game on —
      // a cue at the cue ball, the balls rolling, now and then one dropping into a pocket
      px(pool.x, pool.y, pool.w, pool.h, ROLE.structure); px(pool.x + 2, pool.y + 2, pool.w - 4, pool.h - 4, tint(ROLE.live, ROLE.ground, 0.4))
      for (const [dx, dy] of [[1, 1], [pool.w / 2 - 1, 1], [pool.w - 3, 1], [1, pool.h - 3], [pool.w / 2 - 1, pool.h - 3], [pool.w - 3, pool.h - 3]] as const) px(pool.x + dx, pool.y + dy, 2, 2, ROLE.fieldInk)
      px(pool.x + 3, pool.y + pool.h, 2, 3, ROLE.structure); px(pool.x + pool.w - 5, pool.y + pool.h, 2, 3, ROLE.structure)
      const colours = [ROLE.body, ROLE.alarm, ROLE.key, ROLE.assistant, ROLE.attention, ROLE.edge]
      if (this.at("pool").length === 2) {
        const shot = tick % 60, t = Math.min(1, shot / 20)
        const cue = { x: pool.x + 6 + Math.round(t * 10), y: pool.y + 6 - Math.round(t * 2) }
        if (shot < 4) px(cue.x - 7 + shot, cue.y, 6, 1, ROLE.borderInactive) // the cue drawing back and striking
        px(cue.x, cue.y, 1, 1, ROLE.prose)
        colours.forEach((c, k) => {
          if ((tick >> 6) % 7 === k && shot > 40) return // this one's down
          const bx = pool.x + 14 + ((k * 5 + (shot > 20 ? Math.round((shot - 20) / 8) * (k % 2 ? 1 : -1) : 0) + 20) % 8), by = pool.y + 3 + ((k * 3) % 6)
          px(bx, by, 1, 1, c)
        })
      } else {
        // racked: a triangle at the far end, the cue ball at the near one
        colours.forEach((c, k) => { const row = k < 1 ? 0 : k < 3 ? 1 : 2, col = k < 1 ? 0 : k < 3 ? k - 1 : k - 3; px(pool.x + 16 + row * 2, pool.y + 5 - row + col * 2, 1, 1, c) })
        px(pool.x + 6, pool.y + 6, 1, 1, ROLE.prose)
      }
    })
    // a plant watered enough flowers: the lounge's (its waterer stands at L0 + 22), your office's (at 18)
    for (const [wx, plant] of [[this.z.L0 + 22, { x: this.z.L0 + 4, y: 175 }], [18, { x: 2, y: 159 }]] as const) {
      const n = Math.min(3, Math.floor((this.watered.get(wx) ?? 0) / 300))
      if (n) sc.item(plant.y + 12, () => { for (let k = 0; k < n; k++) sc.blit([".p.", "pyp", ".p."], plant.x + [1, 6, 3][k]!, plant.y - 1 + [0, 1, 3][k]!, { p: ROLE.attention, y: ROLE.body }) })
    }
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
    // the crew's chatter in the slots left: a sticky of its kind's colour, pinned, and its words in the tip
    const tones: Record<string, string> = { encourage: ROLE.live, tease: ROLE.alarm, joke: ROLE.body, comment: ROLE.key, suggestion: ROLE.assistant, reply: ROLE.attention }
    this.cork.slice(0, Math.max(0, 8 - Math.min(8, a.notes.length))).forEach((n, k) => {
      const i = Math.min(8, a.notes.length) + k, x = x0 + 4 + (i % 4) * 12, y = 17 + Math.floor(i / 4) * 10
      sc.px(x, y, 9, 7, tones[n.kind] ?? ROLE.prose); sc.px(x + 1, y + 2, 7, 1, ROLE.fieldInk); sc.px(x + 1, y + 4, 5, 1, ROLE.fieldInk); sc.px(x + 4, y - 1, 1, 2, ROLE.alarm)
      sc.hits.push({ x, y, w: 9, h: 7, tip: `${n.author} (${n.kind}): ${n.body}`, act: { kind: "notes" } })
    })
    sc.hits.push({ x: x0, y: 5, w: 52, h: 34, tip: `${a.notes.length} note(s), ${this.cork.length} on the corkboard: open as a list`, act: { kind: "notes" } })
  }

  /** the suggestion box on the wall: a wooden box with a slot, the slips waiting in it showing over its lid */
  private drawBox(sc: Scene, x0: number) {
    const px = sc.px.bind(sc), n = Math.min(5, this.ideas.length)
    for (let k = 0; k < n; k++) px(x0 + 1 + k * 2, 13 - (k % 2), 2, 4, ROLE.prose)
    px(x0, 16, 10, 12, ROLE.structure); px(x0 + 1, 17, 8, 1, ROLE.borderInactive); px(x0 + 2, 19, 6, 1, ROLE.fieldInk)
    px(x0 + 3, 22, 4, 3, ROLE.body) // its label plate
    sc.hits.push({ x: x0 - 1, y: 10, w: 12, h: 19, tip: `the suggestion box: ${this.ideas.length ? `${this.ideas.length} suggestion(s)` : "empty"} - click to read`, act: { kind: "ideas" } })
  }

  /** windows on the sky as it is outside: night with its stars, dawn and dusk, day */
  /**
   * What the date brings: in October jack-o'-lanterns flickering in the lounge, a cobweb in its
   * corner and, after dark, bats past the windows; in December a little tree with blinking lights.
   * After dark at any time of year the lounge's lamp glows.
   */
  private season(sc: Scene, now: Date) {
    const { L0, M0 } = this.z, f = sc.f, px = sc.px.bind(sc), h = now.getHours(), night = h >= 19 || h < 6
    // a pool of lamplight on the boards under it, brighter at its heart
    if (night) sc.item(83.5, () => { px(L0 + 5, 84, 19, 3, tint(ROLE.body, ROLE.structure, 0.35)); px(L0 + 9, 83, 11, 5, tint(ROLE.body, ROLE.structure, 0.55)) })
    if (now.getMonth() === 9) {
      for (const [x, y] of [[L0 + 42, 146], [OFF_LANE - 10, 182]] as const) sc.item(y, () => sc.blit(["..g..", ".ooo.", "oyoyo", "ooyoo", ".ooo."], x, y - 5, { g: ROLE.live, o: ROLE.structure, y: f % 3 ? ROLE.body : tint(ROLE.body, ROLE.structure, 0.5) }))
      sc.item(BAND, () => { for (let k = 0; k < 6; k++) { px(this.width - 1 - k, BAND + k, 1, 1, tint(ROLE.prose, ROLE.ground, 0.5)); px(this.width - 1 - k * 2, BAND, 1, 1, tint(ROLE.prose, ROLE.ground, 0.4)); px(this.width - 1, BAND + k * 2, 1, 1, tint(ROLE.prose, ROLE.ground, 0.4)) } })
      if (night) sc.overhead.push(() => {
        for (let k = 0; k < 3; k++) {
          const t = sc.tick / 3 + k * 40, x = M0 + 6 + ((t * 1.5) % (L0 + 20 - M0)), y = 12 + k * 7 + Math.round(Math.sin(t / 5) * 4)
          sc.blit((f + k) % 2 ? ["k...k", ".kkk.", "..k.."] : ["kk.kk", "..k.."], Math.round(x), y, { k: tint(ROLE.prose, ROLE.ground, 0.55) })
        }
      })
    } else if (now.getMonth() === 11) {
      sc.item(150, () => {
        sc.blit(["....g....", "...ggg...", "..ggggg..", "...ggg...", "..ggggg..", ".ggggggg.", "ggggggggg", "....o...."], L0 + 42, 140, { g: ROLE.live, o: ROLE.structure })
        for (let k = 0; k < 6; k++) px(L0 + 43 + ((k * 3) % 7), 142 + k, 1, 1, [ROLE.alarm, ROLE.body, ROLE.key][(k + f) % 3]!)
        px(L0 + 46, 139, 1, 1, ROLE.body)
      })
    }
  }

  /**
   * Windows on the sky as it is outside: night with its stars, dawn and dusk, day — and the weather
   * over it (`Server.Office.Weather`): clouds, fog, rain, snow, a storm's lightning. On a clear day
   * the sun comes in, slanting with the hour. A click says what it's like out there.
   */
  private windows(sc: Scene, x0: number, x1: number, now: Date, weather: Agents["weather"]) {
    const h = now.getHours() + now.getMinutes() / 60, tick = sc.tick
    const sky = h < 6 || h >= 20.5 ? "night" : h < 7.5 || h >= 18.5 ? "dusk" : "day"
    const kind = weather?.kind ?? "partly", grey = kind === "cloudy" || kind === "rain" || kind === "snow" || kind === "storm"
    const flash = kind === "storm" && tick % 97 < 2
    for (let x = x0; x + 30 <= x1; x += 36) {
      sc.px(x, 6, 30, 30, ROLE.inactive)
      if (flash) sc.px(x + 1, 7, 28, 28, ROLE.prose)
      else if (sky === "night") {
        sc.px(x + 1, 7, 28, 28, ROLE.ground)
        if (!grey && kind !== "fog") for (let i = 0; i < 5; i++) sc.px(x + 3 + ((i * 11 + x) % 24), 9 + ((i * 7) % 20), 1, 1, ROLE.prose)
      } else if (sky === "dusk") {
        sc.px(x + 1, 7, 28, 10, tint(ROLE.assistant, ROLE.ground, 0.6)); sc.px(x + 1, 17, 28, 10, ROLE.attention); sc.px(x + 1, 27, 28, 8, ROLE.body)
      } else sc.px(x + 1, 7, 28, 28, grey ? tint(ROLE.prose, ROLE.ground, kind === "storm" ? 0.38 : 0.62) : tint(ROLE.key, ROLE.prose, 0.3))
      const cloud = grey ? tint(ROLE.prose, ROLE.ground, sky === "day" ? (kind === "storm" ? 0.55 : 0.85) : 0.35) : ROLE.prose
      if (kind === "partly" || grey) for (let k = 0; k < (grey ? 3 : 1); k++) {
        const cx = x + 1 + ((x >> 3) * 5 + k * 9 + (tick >> 5)) % 22
        sc.px(cx, 10 + k * 5, 8, 2, cloud); sc.px(cx + 2, 9 + k * 5, 4, 1, cloud)
      }
      if (kind === "fog") sc.cv.glow(x + 1, 7, 28, 28, ROLE.prose, sky === "day" ? 0.5 : 0.25)
      if (kind === "rain" || kind === "storm") for (let i = 0; i < 9; i++) {
        const ry = 7 + ((tick * 2 + i * 17 + ((i * i * 5 + x) % 11)) % 26), rx = x + 2 + ((i * 7 + x) % 25) + (ry >> 4)
        sc.px(rx, ry, 1, 2, tint(ROLE.key, ROLE.prose, 0.4))
      }
      if (kind === "snow") for (let i = 0; i < 8; i++) {
        const fy = 7 + ((tick / 2 + i * 11) % 27), fx = x + 2 + ((i * 9 + x) % 25) + Math.round(Math.sin((tick + i * 20) / 12) * 1.5)
        sc.px(fx, Math.floor(fy), 1, 1, ROLE.prose)
      }
      sc.px(x + 14, 6, 2, 30, ROLE.inactive); sc.px(x, 20, 30, 1, ROLE.inactive)
      sc.px(x - 1, 36, 32, 2, ROLE.structure)
      // sun through the glass on a fair day, falling across the floor: east in the morning, west after noon
      if (sky === "day" && (kind === "clear" || kind === "partly")) {
        const slant = Math.max(-1, Math.min(1, (13 - h) / 5)), x2 = x
        sc.item(BAND + 1, () => { for (let j = 0; j < 40; j++) sc.cv.glow(x2 + 3 + Math.round(j * slant * 0.7), BAND + 2 + j, 24, 1, ROLE.body, kind === "clear" ? 0.13 : 0.08) })
      }
      if (weather) sc.hits.push({ x, y: 6, w: 30, h: 30, tip: `outside: ${weather.desc.toLowerCase()}${weather.temp_c === null ? "" : `, ${weather.temp_c}°C`}`, act: { kind: "weather" } })
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
