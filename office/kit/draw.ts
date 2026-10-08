// Drawing the office's life, room-agnostic: the people (seated, walking, typing, asking, talking)
// and Nina, into a Scene — a room's canvas, its ink and its click targets, with everything that has
// a footprint drawn back to front. A room draws its own furniture into the same Scene.
import { Canvas, balloonLines, type Frame, type Hit, type Ink } from "./canvas"
import { tipOf, type BoardCtx } from "./crew"
import { ROLE, tint } from "./palette"
import { FUSS, type Actor, type Cat, type Fussing } from "./sim"
import { ACTIVITY, ARROW, BUBBLE, CAT, figure, GLYPH, paints, PLANE, shirtOf, THOUGHT, type Dir } from "./sprites"
import type { Agents } from "./types"

/** what a room draws besides the snapshot: the picked thread, a ticket being handed out, an open card */
/** what the surface has open, and `tray`: how much of the in-tray you have not read */
export type Focus = { picked: number | null; armed: number | null; person: string | null; tray?: number; board?: BoardCtx }
/** a warm session's mug: three wisps of steam just after the turn, thinning to one as it goes cold, none when cold */
export const steamOf = (warmth: number) => (warmth <= 0 ? 0 : Math.ceil(warmth * 3))
/** a desk monitor's glow for its owner's warmth: lit mid-turn, dimming toward the dark as the session cools */
export const glowOf = (warmth: number) => tint(ROLE.live, ROLE.ground, Math.max(0, Math.min(1, warmth)))
/** a tool running this long (ticks) has its worker sweating */
const SWEAT = 600
/** something with a footprint: drawn in order of `base`, its feet's row, so nearer covers farther */
export type Item = { base: number; draw: () => void }

export class Scene {
  readonly cv: Canvas
  readonly ink: Ink[] = []
  readonly balloons: Ink[] = []
  readonly hits: Hit[] = []
  /** people's click targets — they take a click before the furniture behind them */
  readonly people: Hit[] = []
  readonly items: Item[] = []
  /** drawn after every item: bubbles over heads, the focus arrow */
  readonly overhead: (() => void)[] = []
  /** where each lamp's shade is: a lamp registers itself as it is drawn, and lights once it is dark */
  readonly lamps: [number, number][] = []
  /** it is the dark hours: you are in your pyjamas */
  dark = false
  /** the 400 ms animation frame */
  readonly f: number

  constructor(readonly width: number, readonly height: number, readonly tick: number) {
    this.cv = new Canvas(width, height)
    this.f = Math.floor(tick / 4)
  }
  px(x: number, y: number, w: number, h: number, c: string) { this.cv.px(x, y, w, h, c) }
  blit(rows: string[], x: number, y: number, map: Record<string, string>) { this.cv.blit(rows, x, y, map) }
  text(s: string, x: number, y: number, color: string, size = 12, align: "center" | "left" = "center") { this.ink.push({ t: "text", s, x, y, color, size, align }) }
  item(base: number, draw: () => void) { this.items.push({ base, draw }) }

  /** everything drawn back to front, then overhead; the frame, people's targets first */
  finish(): Frame {
    this.items.sort((p, q) => p.base - q.base).forEach((x) => x.draw())
    this.overhead.forEach((d) => d())
    return { rgba: this.cv.rgba, width: this.width, height: this.height, ink: [...this.ink, ...this.balloons], hits: [...this.people.reverse(), ...this.hits] }
  }
}

/**
 * The people. Seated at a desk or on the couch they face away from you — toward the screen, toward
 * the TV — and turn round only to talk with you; at work their hands move — still while they read
 * or think, flying while they edit, sparks off the keys. Over their heads: a "…" while they think
 * about what you asked, a "!" in your queue, a thought bubble with what they are doing mid-turn
 * (a paper plane off to whoever they delegated to; a tool that runs on, a bead of sweat), an
 * emote, the focus arrow. A turn done, they stretch.
 */
export function drawActors(sc: Scene, actors: Iterable<Actor>, talk: Map<string, { text: string | null }>, a: Agents, focus: Focus) {
  const f = sc.f
  const threadOf = (id: number) => a.threads.find((x) => x.id === id)
  for (const actor of actors) {
    const seat = actor.seat
    const sitting = actor.pose === "sit" && !actor.moving
    const couch = actor.pose === "couch" && !actor.moving
    const step = actor.moving ? 1 + (Math.floor(sc.tick / 2) % 2) : 0
    const shut = (f + actor.look.blink) % 13 === 0
    const talking = talk.has(seat.agent)
    const busy = sitting && seat.thinking && !talking
    const doing = busy ? (seat.doing && ACTIVITY[seat.doing] ? seat.doing : "think") : null
    const working = busy && actor.spot.face !== "down" && doing !== "read" && doing !== "think"
    const stretching = sitting && !seat.thinking && sc.tick < actor.stretch
    // between turns at the desk, the session still warm: leaning back, a mug steaming beside them
    const lounging = sitting && actor.spot.kind === "desk" && !seat.thinking && !talking && !stretching && actor.warmth > 0
    const seatedFace: Dir = talking || actor.spot.face === "down" ? "down" : actor.spot.face
    const rows = figure(actor.look, seat.archetype, !!seat.lead, false, sitting ? seatedFace : couch ? "up" : actor.face, sitting || couch ? "sit" : "stand", step, shut)
    const top = sitting || couch ? actor.y - 14 : actor.y - 20 + (actor.moving && step === 2 ? -1 : 0)
    const left = actor.x - 6
    sc.item(sitting ? actor.y : actor.y + 0.5, () => {
      sc.blit(rows, left, top, paints(shirtOf(seat.archetype), actor.look))
      if (lounging) {
        // hands behind their head, elbows out
        sc.px(left - 1, top + 4, 2, 1, ROLE.prose); sc.px(left + 11, top + 4, 2, 1, ROLE.prose)
        sc.px(left, top + 2, 1, 2, ROLE.prose); sc.px(left + 11, top + 2, 1, 2, ROLE.prose)
      }
      if (working && actor.spot.face === "left") {
        // side-on at a table: a hand reaching for the keys, tapping
        sc.px(left + 1, top + 12 - ((f + actor.y) % 2), 2, 1, ROLE.prose)
      } else if (working) {
        // typing: their elbows, out past their shoulders, take turns — every tick when they edit
        const up = ((doing === "edit" ? sc.tick : f) + actor.x) % 2 === 0
        sc.px(left, top + 11 - (up ? 1 : 0), 1, 1, ROLE.prose)
        sc.px(left + 11, top + 11 - (up ? 0 : 1), 1, 1, ROLE.prose)
        if (doing === "edit") for (const k of [0, 1]) {
          const s = sc.tick + k * 3 + actor.x, rise = s % 4
          sc.px(left + 2 + ((s * 5) % 8), top + 10 - rise * 2, 1, 1, k ? ROLE.key : ROLE.body)
        }
      } else if (!actor.moving && !actor.path.length && actor.pose === "stand") {
        // at a pastime: hands on the joystick, a paddle swinging, a watering can tipped
        const kind = actor.spot.kind
        if (kind === "arcade") { sc.px(left + 2 + (sc.tick % 2), top + 11, 2, 1, ROLE.prose); sc.px(left + 8, top + 11 - (f % 2), 2, 1, ROLE.prose) }
        else if (kind === "pingpong") { const r = actor.face === "right", sw = (sc.tick % 8) < 4 ? 0 : 2; sc.px(r ? left + 12 : left - 2, top + 8 + sw, 2, 3, ROLE.alarm) }
        else if (kind === "plant") { sc.px(left - 4, top + 10, 4, 3, ROLE.key); sc.px(left - 6, top + 10, 2, 1, ROLE.key); sc.px(left - 7, top + 12 + (f % 3) * 2, 1, 1, ROLE.key) }
      } else if (sitting && actor.spot.kind === "read") {
        // a book open in their lap, a page turning over now and then
        sc.px(left + 2, top + 10, 8, 3, ROLE.prose); sc.px(left + 6, top + 10, 1, 3, ROLE.structure)
        if (f % 6 === 0) sc.px(left + 6, top + 8, 3, 2, ROLE.prose)
      } else if (stretching) {
        // arms up over their head, and down again
        const lift = f % 2
        sc.px(left, top + 1 + lift, 1, 10 - lift, ROLE.prose)
        sc.px(left + 11, top + 1 + lift, 1, 10 - lift, ROLE.prose)
        sc.px(left + 1, top + lift, 2, 1, ROLE.prose)
        sc.px(left + 9, top + lift, 2, 1, ROLE.prose)
      }
    })
    if (lounging) sc.item(actor.y + 0.6, () => {
      // the mug on the desk at their elbow: its steam thins as the session cools
      const mx = left - 3, my = top, wisps = steamOf(actor.warmth), haze = tint(ROLE.prose, ROLE.ground, 0.35 + 0.5 * actor.warmth)
      sc.px(mx, my, 2, 2, ROLE.prose); sc.px(mx + 2, my, 1, 1, ROLE.prose)
      for (let k = 0; k < wisps; k++) sc.px(mx + ((sc.tick >> 3) + k) % 2, my - 2 - k * 2, 1, 1, haze)
    })
    else if (actor.mug > sc.tick) sc.item(actor.y + 0.6, () => {
      // a mug, in hand or on the desk beside them, steaming
      const mx = sitting ? left + 12 : left - 1, my = sitting ? top + 4 : top + 12
      sc.px(mx, my, 2, 2, ROLE.prose); sc.px(mx + 2, my, 1, 1, ROLE.prose)
      if ((sc.tick >> 2) % 3) sc.px(mx + ((sc.tick >> 3) % 2), my - 2, 1, 1, tint(ROLE.prose, ROLE.ground, 0.6))
    })
    if (actor.snack > sc.tick && !sitting) sc.item(actor.y + 0.6, () => sc.px(left + 10, top + 12 - ((sc.tick >> 3) % 4 === 0 ? 2 : 0), 2, 2, ROLE.alarm)) // a snack, a bite now and then
    if (sc.tick < actor.five) sc.item(actor.y + 0.6, () => { sc.px(left + 11, top + 1, 1, 10, ROLE.prose); sc.px(left + 10, top, 3, 2, ROLE.prose) }) // a hand up for the high-five
    const agentId = a.bench.find((c) => c.name === seat.agent)?.agent_id ?? null
    sc.people.push({ x: left, y: top, w: 12, h: sitting ? 14 : 20, tip: tipOf(seat, threadOf(seat.thread_id), actor.spot.kind === "queue" ? "in your queue" : actor.moving ? "walking" : lounging ? "between turns at their desk, still warm" : `at the ${actor.spot.kind}`), act: { kind: "person", agentId, name: seat.agent, tid: seat.thread_id > 0 ? seat.thread_id : null } })
    const said = talk.get(seat.agent)
    if (said?.text) sc.balloons.push({ t: "balloon", lines: balloonLines(said.text), cx: actor.x, top })
    sc.overhead.push(() => {
      let above = top - 9
      const bob = f % 2
      if (said && said.text === null) {
        sc.blit(BUBBLE, left + 3, above + bob, { a: ROLE.prose })
        sc.blit(GLYPH["…"]!, left + 4, above + 1 + bob, { k: ROLE.fieldInk })
      } else if (actor.spot.kind === "queue" && !actor.moving) {
        sc.blit(BUBBLE, left + 3, above + bob, { a: ROLE.attention })
        sc.blit(GLYPH["!"]!, left + 4, above + 1 + bob, { k: ROLE.fieldInk })
      } else if (doing) {
        const frames = ACTIVITY[doing]!
        sc.blit(THOUGHT, left + 3, above + bob, { a: ROLE.prose })
        sc.blit(frames[f % frames.length]!, left + 4, above + 1 + bob, { k: ROLE.fieldInk })
        if (doing === "delegate") {
          // off it goes, up and away, again and again
          const t = f % 6
          sc.blit(PLANE, left + 11 + t * 3, above - t * 2, { k: ROLE.prose })
        }
        if (sc.tick - actor.doingSince > SWEAT && doing !== "think") sc.px(left + 1, top + 3 + (f % 3), 1, 2, ROLE.key)
      } else if (actor.emote) {
        sc.blit(BUBBLE, left + 3, above, { a: ROLE.prose })
        sc.blit(GLYPH[actor.emote] ?? GLYPH["…"]!, left + 4, above + 1, { k: ROLE.fieldInk })
      } else above = top - 1
      if (focus.person ? seat.agent === focus.person : seat.thread_id === focus.picked) sc.blit(ARROW, left + 4, above - 4 - bob, { v: ROLE.body })
    })
  }
}

/** bpm present and fast, and the pet isn't asleep, fussed, or mid-zoomies */
export function dancing(mode: string, fuss: Fussing | null, bpm: number | null): boolean {
  return bpm !== null && bpm > 120 && mode !== "sleep" && mode !== "zoom" && !fuss
}

/** Nina, with a light rim so a black cat reads on any floor; `over` is the depth to draw her at when she is up on furniture */
export function drawCat(sc: Scene, c: Cat, over: number | null, bpm: number | null) {
  const f = sc.f
  const grooming = c.mode === "sit" && (f + c.until) % 30 < 6
  const dance = dancing(c.mode, c.fuss, bpm)
  const phase = dance ? Math.floor((sc.tick * bpm!) / 300) % 2 : 0
  const [frames, i] = sc.tick < c.stretch ? [CAT.stretch, 0]
    : c.mode === "zoom" ? [CAT.walk, sc.tick % 4]
      : c.mode === "walk" ? [CAT.walk, Math.floor(sc.tick / 2) % 4]
        : c.mode === "sleep" ? [CAT.sleep, f % 4 < 2 ? 0 : 1]
          : c.mode === "play" ? [CAT.play, c.yarn % 2]
            : grooming ? [CAT.groom, f % 2]
              : f % 13 === 0 ? [CAT.blink, 0] : [CAT.sit, [0, 1, 2, 1][Math.floor(f / 2) % 4]!]
  const rows0 = frames[i]!
  const flipped = dance ? phase === 1 : c.face < 0
  const rows = flipped ? rows0.map((r) => [...r].reverse().join("")) : rows0
  const w = rows[0]!.length, h = rows.length, x = c.x - Math.floor(w / 2), y = c.y - h - (dance ? phase : 0)
  // the zoomies go over everything: she is on the couch, the TV, your desk
  sc.item(c.mode === "zoom" ? 999 : over ?? c.y, () => {
    const r = tint(ROLE.prose, ROLE.ground, 0.55), rim = { k: r, e: r, t: r, c: r, w: r, p: r, g: r, j: r }
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, -1]] as const) sc.blit(rows, x + dx, y + dy, rim)
    // the collar's gems trade colours as they catch the light
    const [g, j] = f % 2 ? [ROLE.key, ROLE.body] : [ROLE.body, ROLE.key]
    sc.blit(rows, x, y, { k: ROLE.fieldInk, t: ROLE.fieldInk, e: ROLE.body, c: ROLE.inactive, w: ROLE.edge, p: ROLE.attention, g, j })
    const gem = rows.findIndex((row) => row.includes("g"))
    if (gem >= 0 && f % 9 === 0) {
      // a twinkle off the collar
      const gx = x + rows[gem]!.indexOf("g"), gy = y + gem - 3
      sc.px(gx, gy - 1, 1, 3, ROLE.prose); sc.px(gx - 1, gy, 3, 1, ROLE.prose)
    }
    if (c.mode === "sleep" && f % 6 < 3) sc.text("z", x + w + 1, y - 1, ROLE.inactive, 10)
    if (c.mode === "zoom") {
      // speed lines behind her, and now and then a "!"
      const back = c.face < 0 ? x + w + 1 : x - 5
      for (const dy of [1, 3]) sc.px(back + ((f + dy) % 2), y + dy, 4, 1, ROLE.inactive)
      if (f % 7 < 2) sc.text("!", c.x, y - 2, ROLE.attention, 11)
    }
    // your hand, stroking her back
    if (sc.tick < c.purr && c.byYou) sc.px(x + 3 + (f % 2) * 2, y + 3, 3, 1, ROLE.prose)
    if (c.fuss) drawFuss(sc, c.fuss, { x, y, w, h })
    sc.hits.push({ x: x - 1, y: y - 2, w: w + 2, h: h + 3, tip: `${c.name} - click to pet her`, act: { kind: "cat" } })
  })
  if (c.said && sc.tick >= c.saidFrom && sc.tick < c.saidUntil) sc.balloons.push({ t: "balloon", lines: balloonLines(c.said), cx: c.x, top: y })
}

/**
 * A worker making a fuss of a pet (`box`, its sprite): a hand on its head (a pat), a hand going at
 * its ear (a scratch), a hand circling its belly, or a treat tossed in an arc from where they are —
 * and hearts rising off it.
 */
export function drawFuss(sc: Scene, fuss: Fussing, box: { x: number; y: number; w: number; h: number }) {
  const left = sc.tick < fuss.until ? fuss.until - sc.tick : 0, t = FUSS - left, f = sc.f
  const head = { x: box.x + box.w - 5, y: box.y }
  if (fuss.kind === "pat") sc.px(head.x - 1, head.y - 2 + (f % 2), 4, 2, ROLE.prose)
  else if (fuss.kind === "scratch") sc.px(head.x + 2 + (sc.tick % 2), head.y + 2, 2, 2, ROLE.prose)
  else if (fuss.kind === "belly") sc.px(box.x + 4 + (f % 3) * 2, box.y + 1, 3, 2, ROLE.prose)
  else if (t < FUSS / 3) {
    // the treat, in flight: from their hand up and over to its mouth
    const k = t / (FUSS / 3), fx = fuss.from.x, fy = fuss.from.y - 12
    const tx = Math.round(fx + (head.x - fx) * k), ty = Math.round(fy + (head.y + 3 - fy) * k - Math.sin(k * Math.PI) * 10)
    sc.px(tx, ty, 2, 2, ROLE.structure)
  } else if (f % 2) sc.px(head.x + 4, head.y + 5, 1, 1, ROLE.structure) // crumbs
  if (t > 4 && f % 3 !== 2) sc.blit(GLYPH["♥"]!, box.x + (t % 2 ? 1 : box.w - 5), box.y - 6 - (t % 8), { k: ROLE.attention })
}

/** a thread shipped: confetti bursting over whoever led it and drifting down, `left` ticks of it to go */
export function drawParty(sc: Scene, x: number, y: number, left: number) {
  const t = 60 - left, colours = [ROLE.attention, ROLE.body, ROLE.key, ROLE.live, ROLE.assistant]
  sc.overhead.push(() => {
    for (let i = 0; i < 24; i++) {
      const a = (i / 24) * Math.PI * 2 + i, burst = Math.min(t, 10) * (1 + (i % 3)) * 0.6
      const px = x + Math.round(Math.cos(a) * burst + Math.sin((t + i) / 3) * 2), py = y - 24 + Math.round(Math.sin(a) * burst * 0.5 + Math.max(0, t - 10) * 0.6)
      sc.px(px, py, i % 2 ? 1 : 2, 1, colours[i % colours.length]!)
    }
  })
}
