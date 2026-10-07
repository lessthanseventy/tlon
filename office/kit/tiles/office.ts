// What's left of the office once every other tile is cut: the boss desk, the in-tray, the beacon,
// the crew board, the manager's and the lead's desks, two tables of four, the filing cabinet, the
// server rack, and your queue.
import { fit, type Measure } from "../canvas"
import type { Focus, Scene } from "../draw"
import { needsYou, tipOf } from "../crew"
import { bossDesk, crewBoard, decor, execDesk } from "../furniture"
import { ROLE, tint } from "../palette"
import { at, type Live, type Rect, type Tile } from "../tiles"
import type { Spot } from "../sim"
import { shirtOf, BIG_PLANT } from "../sprites"
import type { Agents } from "../types"
import {
  BAND, CREW_W, EXEC_Y, OFF_DOOR, OFF_W, SEAT_GAP, SEATS, TABLE_YS, TRAY,
  seatX, type Chair, type Layout, type Zones,
} from "../../rooms/wide"

export function officeTile(z: Zones): Tile<Layout> & { home(l: Layout, agent: string): Spot | null } {
  const { F0, F1 } = z

  function table(sc: Scene, a: Agents, measure: Measure, ty: number, mine: Chair[], focus: Focus, sim: Live) {
    const x0 = F0 + 14, w = SEATS * SEAT_GAP + 4, f = sc.f
    const stateOf = (c: Chair) => {
      const owner = c.agent ? sim.actor(c.agent) : undefined
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
          if (seated) for (let ll = 0; ll < 3; ll++) sc.px(mx + 2, my + 1 + ll * 2, 1 + ((f + ll * 3 + c.x) % 6), 1, ROLE.live)
        }
        if (owner) decor(sc, owner.look, c.x + 11, ty + 12)
      }
    })
    sc.item(ty + 30, () => {
      for (const c of mine) {
        if (!c.agent) continue
        const { owner, p, seated, asks } = stateOf(c)
        if (measure(c.agent.slice(0, 3), 11) <= SEAT_GAP) sc.text(fit(measure, c.agent, SEAT_GAP - 1, 11), c.x, ty + 37, asks ? ROLE.attention : seated ? shirtOf(p?.archetype) : ROLE.inactive, 11)
        if (p && p.thread_id > 0) sc.hits.push({ x: c.x - 5, y: ty + 3, w: 10, h: 9, tip: `${c.agent}'s terminal — click to look over their shoulder`, act: { kind: "terminal", tid: p.thread_id } })
        const hx = c.x - 10, hy = ty, hw = SEAT_GAP, hh = 39
        const where = !owner ? "" : seated ? "working" : owner.spot.kind === "queue" ? "in your queue" : owner.leaving ? "leaving" : owner.path.length ? "walking" : owner.spot.kind === "laptop" ? "on call, at a laptop in the meeting room" : `idle, at the ${owner.spot.kind}`
        const agentId = a.bench.find((b) => b.name === c.agent)?.agent_id ?? null
        sc.hits.push({ x: hx, y: hy, w: hw, h: hh, tip: p ? tipOf(p, a.threads.find((t) => t.id === p.thread_id), where) : c.agent, act: { kind: "person", agentId, name: c.agent, tid: p && p.thread_id > 0 ? p.thread_id : null } })
        if (p && p.thread_id > 0 && p.thread_id === focus.picked) sc.ink.push({ t: "brackets", x: hx, y: hy, w: hw, h: hh, color: ROLE.body })
      }
    })
  }

  return {
    kind: "office",
    blocks(l: Layout): Rect[] {
      const out: Rect[] = [
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
    spots: () => ({
      queue: [
        ...[48, 60, 72, 84].map((x, i) => at(x, 148, 148, i === 0 ? "up" : "left", "queue")),
        at(88, 164, 164, "up", "queue"),
      ],
      // the office-side plant by your desk (the lounge's own plant is lounge's, at L0 + 22)
      plant: [at(18, 168, 168, "left", "plant")],
    }),
    home(l: Layout, agent: string): Spot | null {
      const m = l.desks.find((d) => (d.kind === "manager" || d.kind === "lead") && d.seat?.agent === agent)
      if (m) return { x: seatX(m), y: m.y + 19, aisle: m.y - 3, pose: "sit", face: "down", kind: "desk" }
      const c = l.chairs.find((x) => x.agent === agent)
      return c ? { x: c.x, y: c.table + 26, aisle: c.table + 34, pose: "sit", face: "up", kind: "desk" } : null
    },
    draw(sc: Scene, a: Agents, l: Layout, measure: Measure, sim: Live, focus: Focus) {
      const { desks, chairs } = l
      const px = sc.px.bind(sc), blit = sc.blit.bind(sc)
      for (const d of desks) if (d.kind === "boss") bossDesk(sc, a, d)
      inTray(sc, focus.tray ?? 0)
      beacon(sc, Object.values(a.triage).reduce((n, x) => n + x, 0))
      sc.item(170, () => blit(BIG_PLANT, 2, 159, { l: ROLE.live, o: ROLE.structure }))

      crewBoard(sc, a, measure, F0 + 8, EXEC_Y, CREW_W, 32, 9)
      for (const d of desks) {
        if (d.kind === "boss" || !d.seat) continue
        const owner = sim.actor(d.seat.agent)
        execDesk(sc, a, measure, { ...d, kind: d.kind, seat: d.seat }, !!owner && owner.spot.kind === "desk" && !owner.path.length, 38)
      }
      for (const ty of TABLE_YS) table(sc, a, measure, ty, chairs.filter((c) => c.table === ty), focus, sim)
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
      rack(sc, a, F1 - 60)
    },
  }
}

/** the in-tray on its side table: a sheet for each thing you haven't read (six at most), the top one lit */
function inTray(sc: Scene, unread: number) {
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
function beacon(sc: Scene, stuck: number) {
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
function rack(sc: Scene, a: Agents, x: number) {
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
