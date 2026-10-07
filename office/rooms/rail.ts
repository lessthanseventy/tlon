// The rail room: the office as the desktop's right rail draws it. A three-quarter top-down room W
// logical pixels wide: the whiteboard on the back wall (the open worklines by stage), your glass
// office with the lounge beside it, the floor below. Every walk goes through the corridor down the
// right edge, so nobody needs a path finder. Its life is the kit's Sim; this file is its plan and
// its drawing.
import type { Frame, Measure } from "../kit/canvas"
import { drawActors, drawCat, drawParty, Scene, type Focus } from "../kit/draw"
import { bossDesk, crewBoard, execDesk } from "../kit/furniture"
import { boardColumns, COLS, isManager, needsYou, peopleOf, tipOf, type Act } from "../kit/crew"
import { ROLE, tint } from "../kit/palette"
import { Sim, keyOf, type Actor, type Plan, type Pt, type Spot } from "../kit/sim"
import { BIG_PLANT, COFFEE, COOLER, SCRIBBLES, shirtOf } from "../kit/sprites"
import type { Agents, Seat } from "../kit/types"

export const W = 144
const CX = 137 // the corridor
const BAND = 34 // the back wall ends here
const DOOR_Y = [80, 103] // the gap in your office's glass wall, low, where the queue walks in
const FLOOR = 108 // the desks start here
const BOSS_W = 48, ROW_H = 40
/** the room's height: fixed, so the surface around it never moves */
export const H = FLOOR + 2 * ROW_H + 2

type Desk = { x: number; y: number; w: number; h?: number; kind: "boss" | "manager" | "lead" | "side"; seat?: Seat }
/** a seat at a table, owned by one person (null: free), facing left into it */
type Chair = { x: number; table: number; feet: number; agent: string | null }

// the left half: two tables running down the floor, four seats each, everyone side-on facing into
// one, come up their row from the aisle along the bottom. The right half: the crew board and the
// manager's desk, the lead's desk behind them
const TABLES_X = [6, 34], SIDE_SEATS = 4, SIDE_W = 6, SIDE_GAP = 17, SIDE_TOP = FLOOR + 6, BOTTOM_AISLE = 187
const EXEC_X = 56, CREW_BOARD = { x: 58, w: 28 }, MANAGER_X = 88, EXEC_W = 42, LEAD_X = 73

/**
 * The furniture — fixed: your desk; the manager's and the lead's desks; two tables of four for
 * everyone else. Hiring fills a seat; nothing ever pops in or out.
 */
function layout(a: Agents) {
  const desks: Desk[] = [{ x: 11, y: 42, w: BOSS_W, kind: "boss" }]
  const people = peopleOf(a)
  const managers = people.filter((p) => isManager(a, p)), workers = people.filter((p) => !isManager(a, p))
  if (managers[0]) desks.push({ x: MANAGER_X, y: FLOOR, w: EXEC_W, kind: "manager", seat: managers[0] })
  const lead = workers.find((p) => p.lead), grunts = workers.filter((p) => p !== lead)
  if (lead) desks.push({ x: LEAD_X, y: FLOOR + ROW_H, w: EXEC_W, kind: "lead", seat: lead })
  const chairs: Chair[] = []
  TABLES_X.forEach((tx, t) => {
    desks.push({ x: tx, y: SIDE_TOP, w: SIDE_W, h: SIDE_SEATS * SIDE_GAP, kind: "side" })
    for (let i = 0; i < SIDE_SEATS; i++) chairs.push({ x: tx + SIDE_W + 8, table: tx, feet: SIDE_TOP + 14 + i * SIDE_GAP, agent: grunts[t * SIDE_SEATS + i]?.agent ?? null })
  })
  return { desks, chairs, people }
}
type Layout = ReturnType<typeof layout>

const seatX = (d: Desk) => d.x + Math.round(d.w / 2)
// the whiteboard: its columns' width, and the stickies per row and per column
const COL_W = 22, PER_ROW = 3, PER_COL = 6

// where Nina likes to be: your rug (to nap), your floor, up on your desk beside you, and the lounge
// in front of the couch and by the kitchenette, where whoever is idling can reach her
const CAT_NAP = { x: 35, y: 96 }, CAT_DESK = { x: 25, y: 61 }
// her things in your office: the tower in the right corner, the litter box front-left, the yarn
// and a toy mouse on the rug
const TOWER_X = 59, PERCH_TOP = { x: 64, y: 40 }, PERCH_MID = { x: 64, y: 57 }
const LITTER = { x: 6, y: 72 }, YARN = { x: 55, y: 95 }, PLAY = { x: 49, y: 97 }, MOUSE = { x: 17, y: 97 }
const CAT_LOUNGE = [{ x: 111, y: 84 }, { x: 96, y: 92 }]
const inLounge = (x: number) => x > 70

const RAIL: Plan<Layout> = {
  layout,
  /**
   * Where someone works: the manager and the lead behind their desks facing the floor, come in from
   * the aisle behind; anyone else side-on at a table, come up their row from the aisle along the bottom.
   */
  home(l, agent) {
    const m = l.desks.find((d) => (d.kind === "manager" || d.kind === "lead") && d.seat?.agent === agent)
    if (m) return { x: seatX(m), y: m.y + 19, aisle: m.y - 3, pose: "sit", face: "down", kind: "desk" }
    const c = l.chairs.find((x) => x.agent === agent)
    return c ? { x: c.x, y: c.feet, aisle: BOTTOM_AISLE, pose: "sit", face: "left", kind: "desk" } : null
  },
  // whoever has a question for you stands at your desk; the rest line up behind them, out the door
  queue: [38, 50, 61, 82, 94].map((x, i): Spot => ({ x, y: 100, aisle: 100, pose: "stand", face: i === 0 ? "up" : "left", kind: "queue" })),
  // the lounge: the board up front; the couch below the TV, its back to you; the kitchenette along
  // the glass. The aisles keep every walk off the furniture
  lounge: [
    { x: 78, y: 46, aisle: 50, pose: "stand", face: "up", kind: "board" },
    { x: 90, y: 46, aisle: 50, pose: "stand", face: "up", kind: "board" },
    { x: 104, y: 72, aisle: 80, pose: "couch", face: "up", kind: "couch" },
    { x: 118, y: 72, aisle: 80, pose: "couch", face: "up", kind: "couch" },
    { x: 88, y: 64, aisle: 86, pose: "stand", face: "left", kind: "cooler" },
    { x: 88, y: 80, aisle: 86, pose: "stand", face: "left", kind: "coffee" },
  ],
  exit: { x: CX, y: H - 2, aisle: H - 2, pose: "stand", face: "down", kind: "exit" },
  pen: { x: 84, y: 44, aisle: 44, pose: "stand", face: "up", kind: "note" },
  /** beside whoever is visited: at their desk if they sit at one, else where they stand */
  visit(h: Actor): Spot {
    // someone who sits facing the room (the manager) is visited from in front of their desk
    if (h.spot.kind === "desk" && !h.path.length && h.spot.face === "down") return { x: h.x, y: h.spot.y + 16, aisle: h.spot.y + 16, pose: "stand", face: "up", kind: "visit" }
    const at = h.spot.kind === "desk" && !h.path.length ? h.spot : { x: h.x, y: h.y, aisle: h.y }
    return { x: Math.min(128, at.x + 12), y: at.y, aisle: at.aisle, pose: "stand", face: "left", kind: "visit" }
  },
  // the lounge is full: a stroll down an aisle
  roam(l) {
    const rows = l.desks.filter((d) => d.kind !== "boss")
    const row = rows[Math.floor(Math.random() * rows.length)]
    const y = row ? row.y + 3 : FLOOR + 3
    return { x: 10 + Math.floor(Math.random() * 110), y, aisle: y, pose: "stand", face: "down", kind: "roam" }
  },
  route: (x, from, goal) => [{ x, y: from }, { x: CX, y: from }, { x: CX, y: goal.aisle }, { x: goal.x, y: goal.aisle }, { x: goal.x, y: goal.y }],
  cat: {
    nap: CAT_NAP, desk: CAT_DESK, play: PLAY, litter: LITTER, perches: [PERCH_TOP, PERCH_MID], lounge: CAT_LOUNGE,
    spots: [CAT_NAP, { x: 22, y: 98 }, CAT_DESK, PERCH_TOP, PERCH_MID, PLAY, ...CAT_LOUNGE],
    leaps: [[CAT_NAP, CAT_DESK, PERCH_TOP, PERCH_MID, PLAY]],
    // a spot up off the floor is got to from the floor below it: a hop, a climb, a step in
    via: (p: Pt) =>
      p.x === CAT_DESK.x && p.y === CAT_DESK.y ? { x: CAT_DESK.x, y: 76 }
        : p.x === PERCH_TOP.x && p.y <= PERCH_MID.y ? { x: PERCH_TOP.x, y: 78 }
          : p.x === LITTER.x && p.y === LITTER.y ? { x: LITTER.x, y: 78 } : null,
    // through the gap in the glass wall when she changes rooms
    door: (from, to) => (inLounge(from.x) !== inLounge(to.x) ? [{ x: inLounge(from.x) ? 76 : 64, y: 92 }, { x: inLounge(from.x) ? 64 : 76, y: 92 }] : []),
  },
}

export type { Focus }

export class RailRoom extends Sim<Layout> {
  constructor() { super(RAIL) }

  /** the room as it looks now: its art, what goes over it, and where clicks land */
  render(a: Agents, focus: Focus, measure: Measure): Frame {
    const sc = new Scene(W, H, this.tick), f = sc.f
    const { desks, chairs } = layout(a)
    const px = sc.px.bind(sc), blit = sc.blit.bind(sc), text = sc.text.bind(sc)
    const threadOf = (id: number) => a.threads.find((x) => x.id === id)
    const { ink, hits, items } = sc

    // floors and walls, lighter than the room's black so a black cat reads on every one; each area
    // its own pattern
    const tileA = tint(ROLE.prose, ROLE.ground, 0.27), tileB = tint(ROLE.prose, ROLE.ground, 0.21)
    for (let ty = BAND; ty < H; ty += 8) for (let tx = 0; tx < W; tx += 8) px(tx, ty, 8, 8, ((tx + ty) / 8) % 2 ? tileA : tileB)
    // your office: a carpet, flecked
    px(0, BAND, 71, 104 - BAND, tint(ROLE.meta, ROLE.ground, 0.3))
    for (let y = BAND + 15; y < 104; y += 3) for (let x = (y * 5) % 7; x < 70; x += 7) px(x, y, 1, 1, tint(ROLE.meta, ROLE.ground, 0.4))
    // your office's back wall: wood panels behind the throne, a baseboard, a framed picture
    px(0, BAND, 70, 14, ROLE.structure)
    for (let x = 3; x < 70; x += 6) px(x, BAND, 1, 13, ROLE.borderInactive)
    px(0, BAND + 13, 70, 1, ROLE.body)
    px(8, BAND + 2, 12, 8, ROLE.body); px(9, BAND + 3, 10, 6, ROLE.panel); px(10, BAND + 6, 4, 2, ROLE.live); px(14, BAND + 5, 4, 3, ROLE.attention)
    // your rug: centred on the floor in front of the desk, where whoever waits on you stands
    px(6, 82, 58, 20, ROLE.body); px(7, 83, 56, 18, ROLE.meta)
    for (let i = 0; i < 6; i++) for (const [dx, dy, w] of [[1, 0, 1], [0, 1, 3], [1, 2, 1]] as const) px(12 + i * 9 + dx, 90 + dy, w, 1, ROLE.assistant)
    // the lounge's floorboards, the seams staggered row to row
    const board = tint(ROLE.structure, ROLE.ground, 0.4), seam = tint(ROLE.structure, ROLE.ground, 0.22)
    px(72, BAND, 59, 104 - BAND, board)
    for (let y = BAND + 3; y < 104; y += 4) { px(72, y, 59, 1, seam); px(78 + ((y >> 2) % 3) * 19, y - 3, 1, 3, seam) }
    px(0, 0, W, BAND - 1, ROLE.edge)
    px(0, BAND - 1, W, 1, ROLE.structure)
    // the executive end of the floor: a carpet under the board and the two desks
    px(EXEC_X, FLOOR - 2, 130 - EXEC_X, 2 * ROW_H + 2, tint(ROLE.prose, ROLE.ground, 0.33))
    crewBoard(sc, a, measure, CREW_BOARD.x, FLOOR, CREW_BOARD.w, 38)
    px(CX - 6, H - 4, 12, 3, ROLE.borderInactive)

    // the whiteboard: one sticky per open workline, in its stage's column, in its coworker's colour
    px(3, 2, 138, 30, ROLE.structure)
    px(4, 3, 136, 27, ROLE.ground)
    px(4, 30, 136, 2, ROLE.borderInactive)
    blit(["kk.aa.ll"], 100, 30, { k: ROLE.key, a: ROLE.alarm, l: ROLE.live })
    type Sticky = { tip: string; act: Act; colour: string; mark?: string; blink?: boolean }
    const cols: Sticky[][] = boardColumns(a).map((col) => col.items.map((it): Sticky => {
      if (it.act.kind === "ticket")
        return { tip: `ticket #${it.act.id} ${it.title}\n${it.routed ? "with the manager to staff" : "click: send to the manager, or click a coworker to hand it over"}`, act: it.act, colour: it.routed ? ROLE.meta : ROLE.prose, mark: it.high ? ROLE.alarm : undefined, blink: it.act.id === focus.armed }
      const id = it.act.kind === "thread" ? it.act.tid : 0
      return { tip: `#${id} ${it.title}\n${it.stage}${it.who ? ` · ${it.who}` : ""}${it.asks ? "\nwaiting on you" : ""}`, act: it.act, colour: it.who ? shirtOf(it.archetype) : ROLE.inactive, blink: it.asks }
    }))
    cols.forEach((list, c) => {
      const x0 = 5 + c * COL_W
      if (c) px(x0 - 2, 4, 1, 25, ROLE.edge)
      text(`${COLS[c]} ${list.length}`, x0 + 9, 10, ROLE.key, 10)
      // the header opens the column as a list, where the titles have room
      hits.push({ x: x0 - 1, y: 3, w: COL_W, h: 8, tip: `${COLS[c]!.toLowerCase()}: open as a list`, act: { kind: "column", col: c } })
      const shown = c === 0 ? [...list.slice(0, PER_COL - 1), null] : list.slice(0, PER_COL)
      shown.forEach((n, i) => {
        const sx = x0 + (i % PER_ROW) * 6, sy = 12 + Math.floor(i / PER_ROW) * 5
        if (!n) {
          // the blank sticky at the end of the tickets column: write a new one
          blit(["..k..", ".kkk.", "..k..", "....."], sx, sy, { k: ROLE.key })
          hits.push({ x: sx, y: sy, w: 5, h: 4, tip: "new ticket", act: { kind: "pen" } })
          return
        }
        px(sx, sy, 5, 4, n.blink && f % 2 ? ROLE.attention : n.colour)
        px(sx + 1, sy + 2, 3, 1, ROLE.fieldInk)
        if (n.mark) px(sx + 4, sy, 1, 1, n.mark)
        hits.push({ x: sx, y: sy, w: 5, h: 4, tip: n.tip, act: n.act })
      })
      const more = list.length - shown.filter(Boolean).length
      if (more > 0) text(`+${more}`, x0 + 16, 23, ROLE.key, 10)
    })
    hits.push({ x: 100, y: 29, w: 8, h: 3, tip: "new ticket", act: { kind: "pen" } })
    // the notes strip along the bottom of the board: one squiggle per note, newest first
    px(4, 23, 136, 1, ROLE.edge)
    const shownNotes = a.notes.slice(0, 12)
    shownNotes.forEach((n, i) => {
      const sx = 6 + i * 11
      const c = a.bench.find((b) => b.name === n.author)
      blit(SCRIBBLES[n.id % SCRIBBLES.length]!, sx, 25, { k: c ? shirtOf(c.archetype) : ROLE.prose })
      hits.push({ x: sx, y: 24, w: 10, h: 5, tip: `${n.author}: ${n.body}`, act: { kind: "notes" } })
    })
    if (!shownNotes.length) text("notes land here", 72, 28, ROLE.inactive, 10)
    hits.push({ x: 4, y: 24, w: 136, h: 5, tip: `${a.notes.length} note(s): open as a list`, act: { kind: "notes" } })

    // your office: glass on the lounge side, a door where the queue forms
    for (const [y0, y1] of [[BAND, DOOR_Y[0]!], [DOOR_Y[1]!, 104]] as const) { px(70, y0, 1, y1 - y0, ROLE.edge); px(71, y0, 1, y1 - y0, ROLE.key) }
    px(0, 103, 72, 1, ROLE.structure)

    // the lounge: a rug between the TV and the couch, and the couch's seat (its back, toward you,
    // goes in front of whoever sits there)
    px(98, 50, 30, 7, ROLE.structure)
    px(99, 51, 28, 5, ROLE.borderInactive)
    for (let i = 0; i < 6; i++) px(101 + i * 5, 52 + (i % 2), 2, 2, ROLE.meta)
    px(98, 62, 28, 4, ROLE.borderInactive)

    // everything with a footprint, back to front
    const using = this.using.bind(this)
    // the kitchenette along the glass: the water cooler, then the coffee machine on its cabinet
    items.push({ base: 66, draw: () => {
      blit(COOLER, 73, 50, { k: ROLE.key, m: ROLE.prose, a: ROLE.alarm, o: ROLE.inactive })
      if (using("cooler") && f % 3 === 0) px(75 + (f % 2) * 2, 51, 1, 1, ROLE.ground)
    } })
    items.push({ base: 82, draw: () => {
      px(72, 76, 9, 6, ROLE.structure); px(72, 76, 9, 1, ROLE.borderInactive)
      blit(COFFEE, 73, 69, { m: ROLE.inactive, l: ROLE.live, c: ROLE.prose })
      if (using("coffee")) blit(f % 2 ? ["v.v", ".v."] : [".v.", "v.v"], 75, 66, { v: ROLE.prose })
    } })
    // the TV against the front wall, facing the couch: a show while someone sits there, dark otherwise
    items.push({ base: 49, draw: () => {
      px(102, 44, 24, 3, ROLE.structure); px(103, 47, 2, 2, ROLE.structure); px(123, 47, 2, 2, ROLE.structure)
      px(105, 34, 18, 10, ROLE.inactive)
      if (using("couch")) {
        px(106, 35, 16, 4, ROLE.key); px(106, 39, 16, 4, ROLE.live)
        px(106 + ((f * 3) % 15), 37 - (f % 2), 2, 2, ROLE.body)
      } else { px(106, 35, 16, 8, ROLE.ground); px(119, 36, 2, 1, ROLE.edge) }
    } })
    // a floor lamp by the couch, its shade lit
    items.push({ base: 72, draw: () => {
      px(92, 56, 1, 16, ROLE.inactive); px(91, 72, 3, 1, ROLE.inactive)
      blit(["sssss", ".sss."], 90, 53, { s: ROLE.body })
    } })
    // the couch's back and arms, between you and whoever watches
    items.push({ base: 72.5, draw: () => {
      px(96, 66, 32, 7, ROLE.structure); px(97, 67, 30, 1, ROLE.borderInactive)
      px(95, 62, 3, 11, ROLE.structure); px(126, 62, 3, 11, ROLE.structure)
      px(98, 73, 2, 2, ROLE.structure); px(124, 73, 2, 2, ROLE.structure)
    } })
    items.push({ base: 101, draw: () => blit(BIG_PLANT, 2, 90, { l: ROLE.live, o: ROLE.structure }) })
    items.push({ base: 99, draw: () => blit(BIG_PLANT, 118, 88, { l: ROLE.live, o: ROLE.structure }) })

    const actorAt = (d: Desk) => (d.seat ? this.actors.get(keyOf(d.seat)) : undefined)
    const agentIdOf = (name: string) => a.bench.find((b) => b.name === name)?.agent_id ?? null
    const brackets = (x: number, y: number, w: number, h: number) => ink.push({ t: "brackets", x, y, w, h, color: ROLE.body })
    for (const d of desks) {
      if (d.kind === "boss") { bossDesk(sc, a, d); continue }
      if (d.kind === "manager" || d.kind === "lead") {
        const owner = actorAt(d)
        execDesk(sc, a, measure, { ...d, kind: d.kind, seat: d.seat! }, !!owner && owner.spot.kind === "desk" && !owner.path.length, ROW_H - 1)
        continue
      }
      // a table running down the floor: each seat on its right faces left into it, the monitor
      // turned to them (edge-on to us), its glow on the side they see. No plates — there is no
      // room beside it; the crew board and the tip name them
      const mine = chairs.filter((c) => c.table === d.x)
      const stateOf = (c: Chair) => {
        const owner = c.agent ? this.actors.get(c.agent) : undefined
        return { owner, p: owner?.seat, seated: !!owner && owner.spot.kind === "desk" && !owner.path.length, asks: !!owner && needsYou(threadOf(owner.seat.thread_id)) }
      }
      items.push({ base: d.y, draw: () => {
        px(d.x, d.y, d.w, d.h!, ROLE.borderInactive); px(d.x, d.y, d.w, 1, ROLE.structure); px(d.x + d.w - 1, d.y, 1, d.h!, ROLE.structure)
        px(d.x, d.y + d.h!, d.w, 4, ROLE.structure)
      } })
      for (const c of mine) {
        items.push({ base: c.feet - 1, draw: () => {
          const { seated, asks } = stateOf(c)
          const my = c.feet - 13
          px(d.x + d.w - 4, my, 2, 7, ROLE.inactive); px(d.x + 2, my + 6, 4, 1, ROLE.inactive)
          px(d.x + d.w - 2, my + 1, 1, 5, asks ? (f % 2 ? ROLE.attention : ROLE.raised) : seated ? ROLE.live : ROLE.ground)
        } })
        items.push({ base: c.feet + 1, draw: () => {
          if (!c.agent) return
          const { owner, p, seated } = stateOf(c)
          const hx = c.x - 7, hy = c.feet - 15, hw = 16, hh = SIDE_GAP
          const where = !owner ? "" : seated ? "working" : owner.spot.kind === "queue" ? "in your queue" : owner.leaving ? "leaving" : owner.path.length ? "walking" : `idle, at the ${owner.spot.kind}`
          hits.push({ x: hx, y: hy, w: hw, h: hh, tip: p ? tipOf(p, threadOf(p.thread_id), where) : c.agent, act: { kind: "person", agentId: agentIdOf(c.agent), name: c.agent, tid: p && p.thread_id > 0 ? p.thread_id : null } })
          if (p && p.thread_id > 0 && p.thread_id === focus.picked) brackets(hx, hy, hw, hh)
        } })
      }
    }

    const queued = [...this.actors.values()].filter((x) => x.spot.kind === "queue")
    drawActors(sc, this.actors.values(), this.talk, a, focus)
    const shipper = this.party && [...this.actors.values()].find((x) => x.seat.agent === this.party!.agent)
    if (shipper) drawParty(sc, shipper.x, shipper.y, this.party!.until - this.tick)
    if (queued.length > this.plan.queue.length) sc.overhead.push(() => text(`+${queued.length - this.plan.queue.length + 1}`, 104, 82, ROLE.attention))

    {
      const c = this.cat
      // the cat tower: a sisal post, two carpeted perches, a toy on a string
      items.push({ base: 76, draw: () => {
        const tx = TOWER_X, carpet = ROLE.meta, post = ROLE.inactive, under = tint(ROLE.meta, ROLE.ground, 0.5)
        px(tx + 4, 42, 3, 32, post); for (let y = 44; y < 72; y += 3) px(tx + 4, y, 3, 1, ROLE.borderInactive)
        px(tx, 72, 11, 3, carpet); px(tx, 75, 11, 1, under)
        px(tx, 57, 11, 2, carpet); px(tx, 59, 11, 1, under)
        px(tx - 1, 40, 12, 2, carpet); px(tx - 1, 42, 12, 1, under)
        px(tx + 10, 59, 1, 5, ROLE.prose); px(tx + 9, 64, 3, 2, ROLE.attention)
      } })
      // the litter box: its back and sand behind her, its front lip over her feet
      items.push({ base: 66, draw: () => { px(1, 67, 10, 4, ROLE.key); px(2, 68, 8, 2, ROLE.inactive) } })
      items.push({ base: 74, draw: () => px(1, 71, 10, 2, ROLE.key) })
      // the toys: yarn (rolling while she bats it) and a mouse
      items.push({ base: YARN.y, draw: () => {
        const yx = YARN.x + (c.mode === "play" ? [0, 1, 2, 1][c.yarn]! : 0)
        px(yx, YARN.y - 3, 3, 3, ROLE.attention); px(yx + 1, YARN.y - 2, 1, 1, ROLE.assistant); px(yx - 2, YARN.y - 1, 2, 1, ROLE.attention)
      } })
      items.push({ base: MOUSE.y, draw: () => { px(MOUSE.x, MOUSE.y - 2, 4, 2, ROLE.prose); px(MOUSE.x + 3, MOUSE.y - 3, 1, 1, ROLE.attention); px(MOUSE.x - 2, MOUSE.y - 1, 2, 1, ROLE.attention) } })
      // up on the desk or the tower she is drawn over it, as she is climbing up or down
      drawCat(sc, c, (c.x === CAT_DESK.x || c.x === PERCH_TOP.x) && c.y < 76 ? 80 : null, null)
    }
    if (!a.ok || (a.roster.length === 0 && a.bench.length === 0)) text(a.ok ? "nobody on the clock" : (a.note ?? "channel down"), MANAGER_X + EXEC_W / 2, FLOOR + 20, a.ok ? ROLE.inactive : ROLE.alarm)
    return sc.finish()
  }
}
