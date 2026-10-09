// The office's furniture that every room has, drawn wherever a room puts it: your desk, the
// manager's and the lead's desks, the crew board, the trinkets on a desk. A room places them; their
// look is the same everywhere.
import { fit, type Measure } from "./canvas"
import { crewOf, needsYou, STAGES, tipOf, type CrewStatus } from "./crew"
import type { Scene } from "./draw"
import { ROLE } from "./palette"
import { BOSS_LOOK, DECOR, figure, paints, shirtOf, type Look } from "./sprites"
import type { Agents, Seat } from "./types"

/** a desk's place: its left edge, its top, its width; the seat behind it is at x + w/2 */
export type DeskAt = { x: number; y: number; w: number }
const seatX = (d: DeskAt) => d.x + Math.round(d.w / 2)

/** a desk's trinket (a plant, a mug that steams, a duck, books, a cactus, a photo), its right edge at x */
export function decor(sc: Scene, look: Look, x: number, top: number) {
  const dec = DECOR[look.decor]!
  sc.blit(dec, x - dec[0]!.length, top - dec.length, { l: ROLE.live, o: ROLE.structure, m: ROLE.prose, y: ROLE.body, a: ROLE.attention, k: ROLE.key })
  if (look.decor === 1) sc.blit(sc.f % 2 ? ["v.v.", ".v.."] : [".v.v", "..v."], x - 5, top - 6, { v: ROLE.inactive })
}

/** the crew board: who is on, at a glance — a light each (working, waiting on you, idle) */
export function crewBoard(sc: Scene, a: Agents, measure: Measure, bx: number, by: number, bw: number, bh: number, nameSize = 11) {
  sc.px(bx, by, bw, bh, ROLE.structure); sc.px(bx + 1, by + 1, bw - 2, bh - 2, ROLE.ground)
  sc.text("CREW", bx + bw / 2, by + 6, ROLE.key, 11)
  const light: Record<CrewStatus, string> = { working: ROLE.live, waiting: ROLE.attention, idle: ROLE.inactive }
  // a surface that knows its text's height gets as many rows as fit at it, and a "+n" for the rest;
  // otherwise one column of names while they fit (six), a full office of ten in two, smaller
  const lh = measure.lineHeight?.(nameSize)
  const all = crewOf(a).slice(0, 10)
  const fits = lh ? Math.max(1, Math.floor((bh - 10) / lh)) : 10
  const crew = all.length > fits ? all.slice(0, fits - 1) : all
  const cols = lh ? 1 : crew.length > 6 ? 2 : 1, per = lh ? fits : cols === 1 ? 6 : 5, size = cols === 1 ? nameSize : 9
  crew.forEach((c, i) => {
    const cx = bx + 3 + Math.floor(i / per) * Math.floor(bw / 2), cy = by + 10 + (i % per) * (lh ?? (cols === 1 ? 4.5 : 5))
    sc.px(cx, Math.round(cy), 2, 2, c.status === "waiting" && sc.f % 2 ? ROLE.raised : light[c.status])
    // waiting is said in the name too, not by the light's colour alone
    const name = c.status === "waiting" ? `!${c.name}` : c.name
    sc.text(fit(measure, name, bw / cols - 8, size), cx + 4, cy + 2.5, c.status === "idle" ? ROLE.inactive : ROLE.prose, size, "left")
  })
  if (all.length > crew.length) sc.text(`+${all.length - crew.length}`, bx + 7, by + 10 + crew.length * (lh ?? 4.5) + 2.5, ROLE.key, size, "left")
  sc.hits.push({ x: bx, y: by, w: bw, h: bh, tip: "the crew: who is on what — click for the card", act: { kind: "crew" } })
}

/**
 * You: the big desk, a throne of a chair in your colour, two screens (their backs to us) and a
 * trophy — the one desk better than the manager's. You sit behind it facing the room.
 */
export function bossDesk(sc: Scene, a: Agents, d: DeskAt) {
  const sx = seatX(d), f = sc.f
  sc.item(d.y + 2, () => {
    sc.px(sx - 11, d.y - 2, 22, 20, ROLE.body); sc.px(sx - 10, d.y - 1, 20, 18, ROLE.structure)
    for (let i = 0; i < 3; i++) sc.px(sx - 7 + i * 6, d.y + 1, 2, 2, ROLE.body)
  })
  sc.item(d.y + 25, () => {
    const pj = sc.dark
    sc.blit(figure(BOSS_LOOK, null, false, !pj, "down", "sit", 0, (f + BOSS_LOOK.blink) % 13 === 0), sx - 6, d.y + 5, pj ? { ...paints(ROLE.planner, BOSS_LOOK), p: ROLE.planner } : paints(ROLE.attention, BOSS_LOOK))
  })
  sc.item(d.y + 30, () => {
    for (const mx of [d.x + 1, sx + 6]) { sc.px(mx, d.y + 11, 10, 7, ROLE.inactive); sc.px(mx + 1, d.y + 12, 8, 5, ROLE.edge); sc.px(mx + 4, d.y + 18, 2, 1, ROLE.inactive) }
    sc.px(d.x, d.y + 19, d.w, 2, ROLE.structure)
    sc.px(d.x, d.y + 21, d.w, 1, ROLE.body)
    sc.px(d.x + 1, d.y + 22, d.w - 2, 9, ROLE.borderInactive)
    sc.px(d.x + 8, d.y + 24, d.w - 16, 5, ROLE.structure); sc.px(d.x + 9, d.y + 25, d.w - 18, 3, ROLE.body)
    sc.blit([".yyy.", "yyyyy", ".yyy.", "..y..", ".yyy."], d.x + d.w - 8, d.y + 14, { y: ROLE.body })
    decor(sc, BOSS_LOOK, d.x + d.w - 1, d.y + 19)
    sc.text(a.awaiting ? `you - ${a.awaiting} waiting` : "you", d.x + d.w / 2, d.y + 38 - 2 / 3, ROLE.attention, a.awaiting ? 14 : 12)
    sc.hits.push({ x: d.x, y: d.y + 4, w: d.w, h: 30, tip: "you: hire, file, workspaces, what waits on you", act: { kind: "boss" } })
  })
}

/**
 * The manager's or the lead's desk: a high-backed chair, a desk trimmed in gold, two screens and a
 * lamp; they sit behind it facing the floor. The desk shows what they're on: the manager's in-tray
 * stacks the tickets routed to them, and the lead's desk front lights their thread's workline, stage
 * by stage. `there`: they are sitting at it.
 */
export function execDesk(sc: Scene, a: Agents, measure: Measure, d: DeskAt & { kind: "manager" | "lead"; seat: Seat }, there: boolean, hitH: number) {
  const sx = seatX(d), f = sc.f
  const threadOf = (id: number) => a.threads.find((x) => x.id === id)
  sc.item(d.y + 16, () => {
    sc.px(sx - 7, d.y + 1, 14, 16, ROLE.structure); sc.px(sx - 6, d.y + 2, 12, 14, ROLE.borderInactive)
    sc.px(sx - 7, d.y + 1, 14, 1, ROLE.body)
  })
  sc.lamps.push([d.x + d.w - 5, d.y + 15])
  sc.item(d.y + 31, () => {
    for (const mx of [sx - 14, sx + 4]) { sc.px(mx, d.y + 11, 10, 7, ROLE.inactive); sc.px(mx + 1, d.y + 12, 8, 5, ROLE.edge); sc.px(mx + 4, d.y + 18, 2, 1, ROLE.inactive) }
    sc.px(d.x + 1, d.y + 19, d.w - 2, 2, ROLE.structure)
    sc.px(d.x + 1, d.y + 21, d.w - 2, 1, ROLE.body)
    sc.px(d.x + 2, d.y + 22, d.w - 4, 9, ROLE.borderInactive)
    sc.px(d.x + 8, d.y + 25, 4, 1, ROLE.body); sc.px(d.x + d.w - 12, d.y + 25, 4, 1, ROLE.body)
    sc.blit(["sss.", ".s..", ".s..", "ooo."], d.x + d.w - 6, d.y + 15, { s: ROLE.body, o: ROLE.inactive })
    const th = threadOf(d.seat.thread_id)
    if (d.kind === "manager") {
      const routed = a.tickets.filter((x) => x.routed).length
      sc.px(d.x + 2, d.y + 18, 7, 1, ROLE.inactive)
      for (let i = 0; i < Math.min(routed, 5); i++) sc.px(d.x + 3, d.y + 17 - i, 5, 1, i % 2 ? ROLE.prose : ROLE.inactive)
      sc.text(routed ? `${routed} to staff` : "inbox clear", d.x + d.w / 2, d.y + 29, routed ? ROLE.body : ROLE.inactive, 10)
    } else {
      const at = th?.stage ? (th.stage === "merged" ? STAGES.length : STAGES.indexOf(th.stage)) : -1
      STAGES.forEach((_, i) => sc.px(d.x + 5 + i * 5, d.y + 25, 4, 3,
        i < at ? ROLE.live : i === at ? (needsYou(th) ? (f % 2 ? ROLE.attention : ROLE.raised) : f % 2 ? ROLE.live : ROLE.edge) : ROLE.edge))
      // the stage in words beside the track, so it isn't said by colour alone
      sc.text(th ? th.stage ?? `#${th.id}` : "bench", d.x + 6 + STAGES.length * 5, d.y + 28, needsYou(th) ? ROLE.attention : ROLE.body, 9, "left")
    }
  })
  sc.item(d.y + 32, () => {
    const p = d.seat
    // the name at body size, the role a step smaller beside it
    const tail = d.kind === "manager" ? "(manager)" : "(tech lead)", tw = measure(tail, 9), colour = there ? shirtOf(p.archetype) : ROLE.inactive
    const name = fit(measure, p.agent, d.w - 4 - tw, 12), nw = measure(name, 12), x = d.x + d.w / 2 - (nw + 2 + tw) / 2
    sc.text(name, x, d.y + 38 - 2 / 3, colour, 12, "left"); sc.text(tail, x + nw + 2, d.y + 38 - 2 / 3, colour, 9, "left")
    const agentId = a.bench.find((b) => b.name === p.agent)?.agent_id ?? null
    // their screens: a door into their terminal
    if (p.thread_id > 0) sc.hits.push({ x: sx - 14, y: d.y + 11, w: 28, h: 8, tip: `${p.agent}'s terminal — click to look over their shoulder`, act: { kind: "terminal", tid: p.thread_id } })
    sc.hits.push({ x: d.x, y: d.y, w: d.w, h: hitH, tip: tipOf(p, threadOf(p.thread_id), there ? `at the ${d.kind}'s desk` : "about the office"), act: { kind: "person", agentId, name: p.agent, tid: p.thread_id > 0 ? p.thread_id : null } })
  })
}
