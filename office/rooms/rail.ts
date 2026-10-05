// The rail room: the office as the desktop's right rail draws it (and the TUI's v1). A
// three-quarter top-down room W logical pixels wide: the whiteboard on the back wall (the open
// worklines by stage), your glass office with the lounge beside it, the floor below. Working
// sessions sit at their desks; idle ones wander the lounge; one waiting on you queues at your door.
// Every walk goes through the corridor down the right edge, so nobody needs a path finder.
import { Canvas, balloonLines, fit, plate, type Frame, type Hit, type Ink, type Measure } from "../kit/canvas"
import { boardColumns, COLS, crewOf, isManager, needsYou, peopleOf, STAGES, tipOf, type Act, type CrewStatus } from "../kit/crew"
import { ROLE, tint } from "../kit/palette"
import { ARROW, BIG_PLANT, BOSS_LOOK, BUBBLE, CAT, CAT_NAME, COFFEE, COOLER, DECOR, figure, GLYPH, lookOf, paints, SCRIBBLES, shirtOf, type Dir, type Fav, type Look, type Pose } from "../kit/sprites"
import type { Agents, Seat } from "../kit/types"

export const W = 144
const CX = 137 // the corridor
const BAND = 34 // the back wall ends here
const DOOR_Y = [80, 103] // the gap in your office's glass wall, low, where the queue walks in
const FLOOR = 108 // the desks start here
const BOSS_W = 48, ROW_H = 40
/** the room's height: fixed, so the surface around it never moves */
export const H = FLOOR + 2 * ROW_H + 2

type Kind = Fav | "desk" | "queue" | "roam" | "exit" | "visit" | "note"
type Spot = { x: number; y: number; aisle: number; pose: Pose; face: Dir; kind: Kind }
type Desk = { x: number; y: number; w: number; h?: number; kind: "boss" | "manager" | "lead" | "side"; seat?: Seat }
/** a seat at a table, owned by one person (null: free), facing left into it */
type Chair = { x: number; table: number; feet: number; agent: string | null }
type Actor = {
  seat: Seat; look: Look; x: number; y: number; path: { x: number; y: number }[]
  spot: Spot; spotKey: string; pose: Pose; face: Dir; moving: boolean
  until: number; emote: string | null; emoteUntil: number; leaving: boolean
}
// one figure per person, whatever threads they are on
const keyOf = (r: Seat) => r.agent
const spotKey = (s: Spot) => `${s.kind}:${s.x}:${s.y}`

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
/**
 * Where someone works: the manager and the lead behind their desks facing the floor, come in from
 * the aisle behind; anyone else side-on at a table, come up their row from the aisle along the bottom.
 */
function homeOf(l: Layout, agent: string): Spot | null {
  const m = l.desks.find((d) => (d.kind === "manager" || d.kind === "lead") && d.seat?.agent === agent)
  if (m) return { x: seatX(m), y: m.y + 19, aisle: m.y - 3, pose: "sit", face: "down", kind: "desk" }
  const c = l.chairs.find((x) => x.agent === agent)
  return c ? { x: c.x, y: c.feet, aisle: BOTTOM_AISLE, pose: "sit", face: "left", kind: "desk" } : null
}
// whoever has a question for you stands at your desk; the rest line up behind them, out the door
const QUEUE: Spot[] = [38, 50, 61, 82, 94].map((x, i) => ({ x, y: 100, aisle: 100, pose: "stand", face: i === 0 ? "up" : "left", kind: "queue" }))
// the lounge: the board up front; the couch below the TV, its back to you; the kitchenette along
// the glass. The aisles keep every walk off the furniture
const LOUNGE: Spot[] = [
  { x: 78, y: 46, aisle: 50, pose: "stand", face: "up", kind: "board" },
  { x: 90, y: 46, aisle: 50, pose: "stand", face: "up", kind: "board" },
  { x: 104, y: 72, aisle: 80, pose: "couch", face: "up", kind: "couch" },
  { x: 118, y: 72, aisle: 80, pose: "couch", face: "up", kind: "couch" },
  { x: 88, y: 64, aisle: 86, pose: "stand", face: "left", kind: "cooler" },
  { x: 88, y: 80, aisle: 86, pose: "stand", face: "left", kind: "coffee" },
]
/** beside whoever is visited: at their desk if they sit at one, else where they stand */
function visitSpot(h: Actor): Spot {
  // someone who sits facing the room (the manager) is visited from in front of their desk
  if (h.spot.kind === "desk" && !h.path.length && h.spot.face === "down") return { x: h.x, y: h.spot.y + 16, aisle: h.spot.y + 16, pose: "stand", face: "up", kind: "visit" }
  const at = h.spot.kind === "desk" && !h.path.length ? h.spot : { x: h.x, y: h.y, aisle: h.y }
  return { x: Math.min(128, at.x + 12), y: at.y, aisle: at.aisle, pose: "stand", face: "left", kind: "visit" }
}
const BOARD_PEN: Spot = { x: 84, y: 44, aisle: 44, pose: "stand", face: "up", kind: "note" }
const COL_W = 22, PER_ROW = 3, PER_COL = 6
const VISIT_MS = 60_000, NOTE_MS = 45_000

// where Nina likes to be: your rug (to nap), your floor, up on your desk beside you, and the lounge
// in front of the couch and by the kitchenette, where whoever is idling can reach her
const CAT_NAP = { x: 35, y: 96 }, CAT_DESK = { x: 25, y: 61 }
const CAT_LOUNGE = [{ x: 111, y: 84 }, { x: 96, y: 92 }]
// her things in your office: the tower in the right corner, the litter box front-left, the yarn
// and a toy mouse on the rug
const TOWER_X = 59, PERCH_TOP = { x: 64, y: 40 }, PERCH_MID = { x: 64, y: 57 }
const LITTER = { x: 6, y: 72 }, YARN = { x: 55, y: 95 }, PLAY = { x: 49, y: 97 }, MOUSE = { x: 17, y: 97 }
const CAT_SPOTS = [CAT_NAP, { x: 22, y: 98 }, CAT_DESK, PERCH_TOP, PERCH_MID, PLAY, ...CAT_LOUNGE]
// a spot up off the floor is got to from the floor below it: a hop, a climb, a step in
const viaOf = (p: { x: number; y: number }) =>
  p.x === CAT_DESK.x && p.y === CAT_DESK.y ? { x: CAT_DESK.x, y: 76 }
    : p.x === PERCH_TOP.x && p.y <= PERCH_MID.y ? { x: PERCH_TOP.x, y: 78 }
      : p.x === LITTER.x && p.y === LITTER.y ? { x: LITTER.x, y: 78 } : null
const LOUNGING = new Set(["couch", "cooler", "coffee", "roam"])
const inLounge = (x: number) => x > 70

/** what a room draws besides the snapshot: the picked thread, a ticket being handed out, an open card */
export type Focus = { picked: number | null; armed: number | null; person: string | null }

export class RailRoom {
  private cat = { x: CAT_NAP.x, y: CAT_NAP.y, path: [] as { x: number; y: number }[], mode: "sleep" as "walk" | "sit" | "sleep" | "play", until: 300, face: 1, purr: 0, byYou: false, yarn: 0 }
  private actors = new Map<string, Actor>()
  private tick = 0
  private seeded = false
  /** who you are talking to, by agent name: `text` null while they think, then what they said */
  private talk = new Map<string, { text: string | null; until: number }>()
  private changed = true

  /** a click on Nina: she purrs for a few seconds, and wakes if she was asleep */
  pet() { this.cat.purr = this.tick + 30; this.cat.byYou = false; if (this.cat.mode === "sleep") { this.cat.mode = "sit"; this.cat.until = this.tick + 150 } this.changed = true }
  /** someone was asked something (`text` null) or has answered; an answer shows for ~12 s */
  say(agent: string, text: string | null) { this.talk.set(agent, { text, until: text === null ? Infinity : this.tick + 120 }); this.changed = true }

  /** Nina: naps on your rug, sits and flicks her tail, wanders your floor and the lounge */
  private stepCat(): boolean {
    const c = this.cat
    if (c.path.length) {
      if (this.tick % 2) return false
      const to = c.path[0]!
      c.x += Math.sign(to.x - c.x); c.y += Math.sign(to.y - c.y)
      if (to.x !== c.x) c.face = Math.sign(to.x - c.x)
      if (c.x === to.x && c.y === to.y) c.path.shift()
      if (!c.path.length) {
        const at = (p: { x: number; y: number }) => c.x === p.x && c.y === p.y
        const nap = at(CAT_NAP) || (at(PERCH_TOP) && Math.random() < 0.7)
        c.mode = nap ? "sleep" : at(PLAY) ? "play" : "sit"
        if (at(PLAY)) c.face = 1
        c.until = this.tick + (at(LITTER) ? 60 : nap ? 600 : 150) + Math.floor(Math.random() * (at(LITTER) ? 40 : 300))
      }
      return true
    }
    if (c.mode === "play" && this.tick % 3 === 0) { c.yarn = (c.yarn + 1) % 4; return true }
    // nobody leaves her lonely: you pat her when she is on your desk, and anyone idling in the
    // lounge reaches down to her when she is close
    if (this.tick >= c.purr) {
      if (c.x === CAT_DESK.x && c.y === CAT_DESK.y && Math.random() < 0.02) { c.purr = this.tick + 30; c.byYou = true; return true }
      if (c.mode !== "sleep") for (const a of this.actors.values()) {
        if (a.moving || a.path.length || !LOUNGING.has(a.spot.kind) || Math.abs(a.x - c.x) > 18 || Math.abs(a.y - c.y) > 16 || Math.random() > 0.004) continue
        c.purr = this.tick + 30; c.byYou = false; a.emote = "♥"; a.emoteUntil = this.tick + 30
        return true
      }
    }
    if (this.tick < c.until || this.tick < c.purr) return false
    const company = [...this.actors.values()].some((a) => !a.moving && LOUNGING.has(a.spot.kind))
    const r = Math.random()
    const pick = <T,>(xs: T[]) => xs[Math.floor(Math.random() * xs.length)]!
    const to = company && r < 0.3 ? pick(CAT_LOUNGE)
      : r < 0.45 ? CAT_NAP : r < 0.55 ? CAT_DESK : r < 0.7 ? (Math.random() < 0.5 ? PERCH_TOP : PERCH_MID)
        : r < 0.8 ? PLAY : r < 0.85 ? LITTER : pick(CAT_SPOTS)
    // through the gap in the glass wall when she changes rooms
    const door = inLounge(c.x) !== inLounge(to.x) ? [{ x: inLounge(c.x) ? 76 : 64, y: 92 }, { x: inLounge(c.x) ? 64 : 76, y: 92 }] : []
    const down = viaOf(c), up = viaOf(to)
    c.path = [...(down ? [down] : []), ...door, ...(up ? [up] : []), to]; c.mode = "walk"
    return true
  }

  /**
   * Advance one tick (100 ms): retarget everyone from the roster, then walk. True when the room
   * looks different — someone moved, or the 400 ms animation frame turned — so the surface redraws
   * only then.
   */
  step(a: Agents): boolean {
    this.tick++
    let changed = this.changed || this.tick % 4 === 0
    this.changed = false
    for (const [k, v] of this.talk) if (this.tick > v.until) { this.talk.delete(k); changed = true }
    if (this.stepCat()) changed = true
    const l = layout(a)
    const exit: Spot = { x: CX, y: H - 2, aisle: H - 2, pose: "stand", face: "down", kind: "exit" }
    const threadOf = (id: number) => a.threads.find((t) => t.id === id)
    const asks = l.people.filter((p) => needsYou(threadOf(p.thread_id))).sort((p, q) => p.thread_id - q.thread_id)
    const live = new Set(l.people.map(keyOf))
    for (const r of l.people) {
      const k = keyOf(r)
      const actor = this.actors.get(k)
      if (actor) { actor.seat = r; actor.leaving = false; continue }
      const at = this.seeded ? exit : homeOf(l, r.agent) ?? LOUNGE[this.actors.size % LOUNGE.length]!
      this.actors.set(k, { seat: r, look: lookOf(r.agent), x: at.x, y: at.y, path: [], spot: at, spotKey: this.seeded ? "" : spotKey(at), pose: at.pose, face: at.face, moving: false, until: 0, emote: null, emoteUntil: 0, leaving: false })
    }
    if (a.ok) this.seeded = true
    for (const [k, actor] of this.actors) if (!live.has(k)) actor.leaving = true

    // a consult walks the asker over to whoever they asked; a note walks its author to the board
    const now = Date.now()
    const visiting = new Map(a.visits.filter((v) => now - Date.parse(v.at) < VISIT_MS).map((v) => [v.from, v.to]))
    const writing = new Set(a.notes.filter((n) => now - Date.parse(n.at) < NOTE_MS).map((n) => n.author))
    let host: Actor | undefined
    const held = new Set([...this.actors.values()].map((x) => x.spotKey))
    for (const [k, actor] of this.actors) {
      const slot = asks.findIndex((r) => keyOf(r) === k)
      const home = homeOf(l, actor.seat.agent)
      let goal: Spot
      if (actor.leaving) goal = exit
      else if (slot >= 0) goal = QUEUE[Math.min(slot, QUEUE.length - 1)]!
      else if (visiting.has(actor.seat.agent) && (host = this.find(visiting.get(actor.seat.agent)!))) goal = visitSpot(host)
      else if (writing.has(actor.seat.agent)) goal = BOARD_PEN
      else if (actor.seat.warm && home) goal = home
      else goal = this.idleGoal(actor, held, l.desks)
      const gk = spotKey(goal)
      if (gk !== actor.spotKey) {
        held.delete(actor.spotKey); held.add(gk)
        const from = actor.path.length === 0 && actor.spot.kind === "desk" ? actor.spot.aisle : actor.y
        actor.path = [{ x: actor.x, y: from }, { x: CX, y: from }, { x: CX, y: goal.aisle }, { x: goal.x, y: goal.aisle }, { x: goal.x, y: goal.y }]
        actor.spot = goal; actor.spotKey = gk; actor.pose = "stand"
        actor.until = this.tick + 80 + Math.floor(Math.random() * 120)
      }
      // someone you are talking to stops where they are and faces you until they have answered
      if (this.talk.get(actor.seat.agent)?.text === null) { actor.moving = false; if (actor.pose === "stand") actor.face = "down" }
      else this.walk(actor, goal.kind === "desk" || goal.kind === "queue" || !actor.look.slow ? 2 : 1)
      if (actor.moving) changed = true
      else if (goal.kind === "visit" || goal.kind === "note") {
        // arrived: the two of them talk, or the pen moves
        const e = goal.kind === "note" ? "✎" : "~"
        if (actor.emote !== e) { actor.emote = e; changed = true }
        actor.emoteUntil = this.tick + 5
        const h = goal.kind === "visit" ? this.find(visiting.get(actor.seat.agent)!) : undefined
        if (h && h.emote !== "~") { h.emote = "~"; h.emoteUntil = this.tick + 5; changed = true }
      }
      if (actor.leaving && !actor.moving && actor.path.length === 0) { this.actors.delete(k); changed = true; continue }
      if (actor.emote && this.tick > actor.emoteUntil) { actor.emote = null; changed = true }
      if (!actor.emote && !actor.moving && Math.random() < 0.006) {
        const e: Record<string, string> = { board: "?", cooler: "~", coffee: "♥" }
        actor.emote = e[actor.spot.kind] ?? actor.look.emote
        actor.emoteUntil = this.tick + 25
        changed = true
      }
    }
    return changed
  }

  /** where someone is now, by name — at their desk before anywhere else */
  private find(agent: string): Actor | undefined {
    const all = [...this.actors.values()].filter((x) => x.seat.agent === agent && !x.leaving)
    return all.find((x) => x.spot.kind === "desk") ?? all[0]
  }

  private idleGoal(actor: Actor, held: Set<string>, desks: Desk[]): Spot {
    const cur = actor.spot
    const idle = cur.kind === "board" || cur.kind === "couch" || cur.kind === "cooler" || cur.kind === "coffee" || cur.kind === "roam"
    if (idle && this.tick < actor.until) return cur
    const free = LOUNGE.filter((s) => !held.has(spotKey(s)) && spotKey(s) !== actor.spotKey)
    const fav = free.filter((s) => s.kind === actor.look.fav)
    const pool = fav.length && Math.random() < 0.6 ? fav : free
    const pick = pool[Math.floor(Math.random() * pool.length)]
    if (pick) return pick
    // the lounge is full: a stroll down an aisle
    const rows = desks.filter((d) => d.kind !== "boss")
    const row = rows[Math.floor(Math.random() * rows.length)]
    const y = row ? row.y + 3 : FLOOR + 3
    return { x: 10 + Math.floor(Math.random() * 110), y, aisle: y, pose: "stand", face: "down", kind: "roam" }
  }

  private walk(actor: Actor, speed: number) {
    actor.moving = false
    let budget = speed
    while (budget > 0 && actor.path.length) {
      const p = actor.path[0]!
      const dx = p.x - actor.x, dy = p.y - actor.y
      if (dx === 0 && dy === 0) { actor.path.shift(); continue }
      actor.moving = true
      if (dx !== 0) { const s = Math.sign(dx) * Math.min(budget, Math.abs(dx)); actor.x += s; budget -= Math.abs(s); actor.face = dx < 0 ? "left" : "right" }
      else { const s = Math.sign(dy) * Math.min(budget, Math.abs(dy)); actor.y += s; budget -= Math.abs(s); actor.face = dy < 0 ? "up" : "down" }
    }
    if (!actor.path.length) { actor.pose = actor.spot.pose; if (!actor.moving) actor.face = actor.spot.face }
  }

  /** the room as it looks now: its art, what goes over it, and where clicks land */
  render(a: Agents, focus: Focus, measure: Measure): Frame {
    const t = this.tick, f = Math.floor(t / 4)
    const { desks, chairs } = layout(a)
    const cv = new Canvas(W, H)
    const px = cv.px.bind(cv), blit = cv.blit.bind(cv)
    const threadOf = (id: number) => a.threads.find((x) => x.id === id)
    const ink: Ink[] = []
    const balloons: Ink[] = []
    const text = (s: string, x: number, y: number, color: string, size = 12, align: "center" | "left" = "center") => ink.push({ t: "text", s, x, y, color, size, align })
    const hits: Hit[] = []
    const people: Hit[] = []
    const shirt = (r?: { archetype?: string | null }) => shirtOf(r?.archetype)

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
    // the crew board: who is on, at a glance — a light each (working, waiting on you, idle)
    {
      // one column of names while they fit (six); a full office of ten takes two, smaller
      const bx = CREW_BOARD.x, bw = CREW_BOARD.w, by = FLOOR, bh = 38
      px(bx, by, bw, bh, ROLE.structure); px(bx + 1, by + 1, bw - 2, bh - 2, ROLE.ground)
      text("CREW", bx + bw / 2, by + 6, ROLE.key, 11)
      const light: Record<CrewStatus, string> = { working: ROLE.live, waiting: ROLE.attention, idle: ROLE.inactive }
      const crew = crewOf(a).slice(0, 10), cols = crew.length > 6 ? 2 : 1, per = cols === 1 ? 6 : 5, size = cols === 1 ? 11 : 9
      crew.forEach((c, i) => {
        const cx = bx + 3 + Math.floor(i / per) * Math.floor(bw / 2), cy = by + 10 + (i % per) * (cols === 1 ? 4.5 : 5)
        px(cx, Math.round(cy), 2, 2, c.status === "waiting" && f % 2 ? ROLE.raised : light[c.status])
        text(fit(measure, c.name, bw / cols - 8, size), cx + 4, cy + 2.5, c.status === "idle" ? ROLE.inactive : ROLE.prose, size, "left")
      })
      hits.push({ x: bx, y: by, w: bw, h: bh, tip: "the crew: who is on what — click for the card", act: { kind: "crew" } })
    }
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
    type Item = { base: number; draw: () => void }
    const items: Item[] = []
    const overhead: (() => void)[] = []
    const using = (kind: Kind) => [...this.actors.values()].some((x) => x.spot.kind === kind && !x.moving)
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
    const decor = (look: Look, x: number, top: number) => {
      const dec = DECOR[look.decor]!
      blit(dec, x - dec[0]!.length, top - dec.length, { l: ROLE.live, o: ROLE.structure, m: ROLE.prose, y: ROLE.body, a: ROLE.attention, k: ROLE.key })
      if (look.decor === 1) blit(f % 2 ? ["v.v.", ".v.."] : [".v.v", "..v."], x - 5, top - 6, { v: ROLE.inactive })
    }
    for (const d of desks) {
      const sx = seatX(d)
      if (d.kind === "boss") {
        // you: the corner office's big desk, a throne of a chair in your colour, two screens (their
        // backs to us) and a trophy — the one desk better than the manager's
        items.push({ base: d.y + 2, draw: () => {
          px(sx - 11, d.y - 2, 22, 20, ROLE.body); px(sx - 10, d.y - 1, 20, 18, ROLE.structure)
          for (let i = 0; i < 3; i++) px(sx - 7 + i * 6, d.y + 1, 2, 2, ROLE.body)
        } })
        items.push({ base: d.y + 25, draw: () => {
          blit(figure(BOSS_LOOK, null, false, true, "down", "sit", 0, (f + BOSS_LOOK.blink) % 13 === 0), sx - 6, d.y + 5, paints(ROLE.attention, BOSS_LOOK))
        } })
        items.push({ base: d.y + 30, draw: () => {
          for (const mx of [d.x + 1, sx + 6]) { px(mx, d.y + 11, 10, 7, ROLE.inactive); px(mx + 1, d.y + 12, 8, 5, ROLE.edge); px(mx + 4, d.y + 18, 2, 1, ROLE.inactive) }
          px(d.x, d.y + 19, d.w, 2, ROLE.structure)
          px(d.x, d.y + 21, d.w, 1, ROLE.body)
          px(d.x + 1, d.y + 22, d.w - 2, 9, ROLE.borderInactive)
          px(d.x + 8, d.y + 24, d.w - 16, 5, ROLE.structure); px(d.x + 9, d.y + 25, d.w - 18, 3, ROLE.body)
          blit([".yyy.", "yyyyy", ".yyy.", "..y..", ".yyy."], d.x + d.w - 8, d.y + 14, { y: ROLE.body })
          decor(BOSS_LOOK, d.x + d.w - 1, d.y + 19)
          text(a.awaiting ? `you - ${a.awaiting} waiting` : "you", d.x + d.w / 2, d.y + 38 - 2 / 3, ROLE.attention)
          hits.push({ x: d.x, y: d.y + 4, w: d.w, h: 30, tip: "you: hire, file, workspaces, what waits on you", act: { kind: "boss" } })
        } })
        continue
      }
      if (d.kind === "manager" || d.kind === "lead") {
        // the manager's and the lead's desks: a high-backed chair, a desk trimmed in gold, two
        // screens and a lamp; they sit behind it facing the floor, like you do in your office. The
        // desk shows what they're on: the manager's in-tray stacks the tickets routed to them, and
        // the lead's desk front lights their thread's workline, stage by stage
        const owner = actorAt(d)
        const there = !!owner && owner.spot.kind === "desk" && !owner.path.length
        items.push({ base: d.y + 16, draw: () => {
          px(sx - 7, d.y + 1, 14, 16, ROLE.structure); px(sx - 6, d.y + 2, 12, 14, ROLE.borderInactive)
          px(sx - 7, d.y + 1, 14, 1, ROLE.body)
        } })
        items.push({ base: d.y + 31, draw: () => {
          for (const mx of [sx - 14, sx + 4]) { px(mx, d.y + 11, 10, 7, ROLE.inactive); px(mx + 1, d.y + 12, 8, 5, ROLE.edge); px(mx + 4, d.y + 18, 2, 1, ROLE.inactive) }
          px(d.x + 1, d.y + 19, d.w - 2, 2, ROLE.structure)
          px(d.x + 1, d.y + 21, d.w - 2, 1, ROLE.body)
          px(d.x + 2, d.y + 22, d.w - 4, 9, ROLE.borderInactive)
          px(d.x + 8, d.y + 25, 4, 1, ROLE.body); px(d.x + d.w - 12, d.y + 25, 4, 1, ROLE.body)
          blit(["sss.", ".s..", ".s..", "ooo."], d.x + d.w - 6, d.y + 15, { s: ROLE.body, o: ROLE.inactive })
          const th = threadOf(d.seat!.thread_id)
          if (d.kind === "manager") {
            const routed = a.tickets.filter((x) => x.routed).length
            px(d.x + 2, d.y + 18, 7, 1, ROLE.inactive)
            for (let i = 0; i < Math.min(routed, 5); i++) px(d.x + 3, d.y + 17 - i, 5, 1, i % 2 ? ROLE.prose : ROLE.inactive)
            text(routed ? `${routed} to staff` : "inbox clear", d.x + d.w / 2, d.y + 29, routed ? ROLE.body : ROLE.inactive, 10)
          } else {
            const at = th?.stage ? (th.stage === "merged" ? STAGES.length : STAGES.indexOf(th.stage)) : -1
            STAGES.forEach((_, i) => px(d.x + 5 + i * 5, d.y + 25, 4, 3,
              i < at ? ROLE.live : i === at ? (needsYou(th) ? (f % 2 ? ROLE.attention : ROLE.raised) : f % 2 ? ROLE.live : ROLE.edge) : ROLE.edge))
            text(th ? `#${th.id}${th.stage ? ` ${th.stage}` : ""}` : "bench", d.x + d.w - 8, d.y + 28, needsYou(th) ? ROLE.attention : ROLE.body, 10)
          }
        } })
        items.push({ base: d.y + 32, draw: () => {
          const p = d.seat!
          text(plate(measure, p.agent, d.kind === "manager" ? "(manager)" : "(lead)", d.w - 2), d.x + d.w / 2, d.y + 38 - 2 / 3, there ? shirt(p) : ROLE.inactive)
          hits.push({ x: d.x, y: d.y, w: d.w, h: ROW_H - 1, tip: tipOf(p, threadOf(p.thread_id), there ? `at the ${d.kind}'s desk` : "about the office"), act: { kind: "person", agentId: agentIdOf(p.agent), name: p.agent, tid: p.thread_id > 0 ? p.thread_id : null } })
        } })
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
    for (const actor of this.actors.values()) {
      const seat = actor.seat
      const sitting = actor.pose === "sit" && !actor.moving
      const couch = actor.pose === "couch" && !actor.moving
      const step = actor.moving ? 1 + (Math.floor(t / 2) % 2) : 0
      const shut = (f + actor.look.blink) % 13 === 0
      // seated, at a desk or on the couch, they face away from you — toward the screen, toward
      // the TV — and turn round only to talk with you
      const talking = this.talk.has(seat.agent)
      const working = sitting && seat.warm && !talking && actor.spot.face !== "down"
      const seatedFace: Dir = talking || actor.spot.face === "down" ? "down" : actor.spot.face
      const rows = figure(actor.look, seat.archetype, !!seat.lead, false, sitting ? seatedFace : couch ? "up" : actor.face, sitting || couch ? "sit" : "stand", step, shut)
      const top = sitting || couch ? actor.y - 14 : actor.y - 20 + (actor.moving && step === 2 ? -1 : 0)
      const left = actor.x - 6
      const th = threadOf(seat.thread_id)
      items.push({ base: sitting ? actor.y : actor.y + 0.5, draw: () => {
        blit(rows, left, top, paints(shirt(seat), actor.look))
        if (working && actor.spot.face === "left") {
          // side-on at a table: a hand reaching for the keys, tapping
          px(left + 1, top + 12 - ((f + actor.y) % 2), 2, 1, ROLE.prose)
        } else if (working) {
          // typing: their elbows, out past their shoulders, take turns
          const up = (f + actor.x) % 2 === 0
          px(left, top + 11 - (up ? 1 : 0), 1, 1, ROLE.prose)
          px(left + 11, top + 11 - (up ? 0 : 1), 1, 1, ROLE.prose)
        }
      } })
      const agentId = a.bench.find((c) => c.name === seat.agent)?.agent_id ?? null
      people.push({ x: left, y: top, w: 12, h: sitting ? 14 : 20, tip: tipOf(seat, th, actor.spot.kind === "queue" ? "in your queue" : actor.moving ? "walking" : `at the ${actor.spot.kind}`), act: { kind: "person", agentId, name: seat.agent, tid: seat.thread_id > 0 ? seat.thread_id : null } })
      const talk = this.talk.get(seat.agent)
      if (talk?.text) balloons.push({ t: "balloon", lines: balloonLines(talk.text), cx: actor.x, top })
      overhead.push(() => {
        let above = top - 9
        const bob = f % 2
        if (talk && talk.text === null) {
          blit(BUBBLE, left + 3, above + bob, { a: ROLE.prose })
          blit(GLYPH["…"]!, left + 4, above + 1 + bob, { k: ROLE.fieldInk })
        } else if (actor.spot.kind === "queue" && !actor.moving) {
          blit(BUBBLE, left + 3, above + bob, { a: ROLE.attention })
          blit(GLYPH["!"]!, left + 4, above + 1 + bob, { k: ROLE.fieldInk })
        } else if (actor.emote) {
          blit(BUBBLE, left + 3, above, { a: ROLE.prose })
          blit(GLYPH[actor.emote] ?? GLYPH["…"]!, left + 4, above + 1, { k: ROLE.fieldInk })
        } else above = top - 1
        if (focus.person ? seat.agent === focus.person : seat.thread_id === focus.picked) blit(ARROW, left + 4, above - 4 - bob, { v: ROLE.body })
      })
    }
    if (queued.length > QUEUE.length) overhead.push(() => text(`+${queued.length - QUEUE.length + 1}`, 104, 82, ROLE.attention))

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
      const frames = CAT[c.mode], rows0 = frames[c.mode === "walk" ? (c.x + c.y) % 2 : c.mode === "play" ? c.yarn % 2 : c.mode === "sit" && f % 5 === 0 ? 1 : 0]!
      const rows = c.face < 0 ? rows0.map((r) => [...r].reverse().join("")) : rows0
      const w = rows[0]!.length, h = rows.length, x = c.x - Math.floor(w / 2), y = c.y - h
      // up on the desk or the tower she is drawn over it, as she is climbing up or down
      const up = (c.x === CAT_DESK.x || c.x === PERCH_TOP.x) && c.y < 76
      items.push({ base: up ? 80 : c.y, draw: () => {
        // a light rim, so a black cat reads on any floor
        const r = tint(ROLE.prose, ROLE.ground, 0.55), rim = { k: r, e: r, t: r, c: r, w: r }
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, -1]] as const) blit(rows, x + dx, y + dy, rim)
        blit(rows, x, y, { k: ROLE.fieldInk, t: ROLE.fieldInk, e: ROLE.body, c: ROLE.inactive, w: ROLE.edge })
        if (c.mode === "sleep" && f % 6 < 3) text("z", x + w + 1, y - 1, ROLE.inactive, 10)
        if (this.tick < c.purr) {
          text(`${CAT_NAME}: prr`, c.x, y - 2, ROLE.attention, 11)
          // your hand, stroking her back
          if (c.byYou) px(x + 3 + (f % 2) * 2, y + 2, 3, 1, ROLE.prose)
        }
        hits.push({ x: x - 1, y: y - 2, w: w + 2, h: h + 3, tip: `${CAT_NAME} - click to pet her`, act: { kind: "cat" } })
      } })
    }
    items.sort((p, q) => p.base - q.base).forEach((x) => x.draw())
    overhead.forEach((d) => d())
    if (!a.ok || (a.roster.length === 0 && a.bench.length === 0)) text(a.ok ? "nobody on the clock" : (a.note ?? "channel down"), MANAGER_X + EXEC_W / 2, FLOOR + 20, a.ok ? ROLE.inactive : ROLE.alarm)
    // a click lands on a person before the desk behind them
    return { rgba: cv.rgba, width: W, height: H, ink: [...ink, ...balloons], hits: [...people.reverse(), ...hits] }
  }
}
