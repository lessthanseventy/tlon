// The games corner: arcade cabinets, the ping-pong table, foosball, pool, and the aquarium.
import type { Measure } from "../canvas"
import type { Scene } from "../draw"
import { ROLE, tint } from "../palette"
import { at, type Live, type Rect, type Tile } from "../tiles"
import type { Agents } from "../types"
import type { Actor } from "../sim"
import { corner, fishWatch, type Layout, type Zones } from "../../rooms/wide"

export function gamesTile(z: Zones): Tile<Layout> & {
  step(tick: number, at: (kind: string) => Actor[], actors: Map<string, Actor>): void
  highScores(): ({ name: string; score: number } | null)[]
} {
  const { table: t, cabinets, tank, foos, pool } = corner(z)
  const ends = [{ x: t.x - 4, y: t.y + 6 }, { x: t.x + t.w + 4, y: t.y + 6 }]
  const highs: ({ name: string; score: number } | null)[] = [null, null]
  const runs = new Map<string, { cab: number; score: number }>()
  let fanfare = 0

  return {
    kind: "games",
    blocks: (): Rect[] => [t, ...cabinets, tank, foos, pool],
    spots: () => ({
      arcade: cabinets.map((c) => at(c.x + 6, c.y + c.h + 10, c.y + c.h + 10, "up", "arcade")),
      pingpong: [at(ends[0]!.x, ends[0]!.y, t.y + t.h + 12, "right", "pingpong", ends[1]), at(ends[1]!.x, ends[1]!.y, t.y + t.h + 12, "left", "pingpong", ends[0])],
      aquarium: [at(tank.x + 8, tank.y + tank.h + 10, tank.y + tank.h + 10, "up", "aquarium"), at(tank.x + 22, tank.y + tank.h + 10, tank.y + tank.h + 10, "up", "aquarium")],
      foosball: [at(foos.x - 4, foos.y + 6, 184, "right", "foosball", { x: foos.x + foos.w + 4, y: foos.y + 6 }), at(foos.x + foos.w + 4, foos.y + 6, 184, "left", "foosball", { x: foos.x - 4, y: foos.y + 6 })],
      pool: [at(pool.x + 3, pool.y - 4, pool.y - 4, "down", "pool", { x: pool.x + 23, y: pool.y - 4 }), at(pool.x + 23, pool.y - 4, pool.y - 4, "down", "pool", { x: pool.x + 3, y: pool.y - 4 })],
    }),
    draw(sc: Scene, _a: Agents, _l: Layout, _m: Measure, sim: Live) {
      const f = sc.f, tick = sc.tick, px = sc.px.bind(sc)
      sc.item(t.y + t.h, () => {
        px(t.x + 2, t.y + 8, 2, 4, ROLE.inactive); px(t.x + t.w - 4, t.y + 8, 2, 4, ROLE.inactive)
        px(t.x, t.y, t.w, 8, tint(ROLE.live, ROLE.ground, 0.4)); px(t.x, t.y, t.w, 1, ROLE.prose); px(t.x, t.y + 7, t.w, 1, ROLE.prose)
        px(t.x + t.w / 2 - 1, t.y - 2, 2, 9, tint(ROLE.prose, ROLE.ground, 0.7))
      })
      const players = sim.at("pingpong")
      if (players.length === 2) {
        const p = (tick % 16) / 8, k = p < 1 ? p : 2 - p, x = Math.round(t.x + 2 + k * (t.w - 4)), y = Math.round(t.y + 3 - Math.sin(k * Math.PI) * 7)
        sc.overhead.push(() => px(x, y, 2, 2, ROLE.body))
      }
      cabinets.forEach((c, i) => sc.item(c.y + c.h, () => {
        const body = i ? ROLE.assistant : ROLE.planner, playing = sim.at("arcade").some((a) => Math.abs(a.x - (c.x + 6)) < 3)
        px(c.x, c.y, c.w, c.h, tint(body, ROLE.ground, 0.55)); px(c.x, c.y, c.w, 3, tick < fanfare ? (tick % 2 ? ROLE.attention : ROLE.body) : f % 4 ? body : ROLE.body)
        px(c.x + 2, c.y + 4, 8, 7, ROLE.ground)
        if (playing) {
          const dx = Math.floor(f / 2) % 3
          for (let k = 0; k < 3; k++) px(c.x + 2 + dx + k * 2, c.y + 5, 1, 1, ROLE.live)
          px(c.x + 3 + ((f * 3) % 6), c.y + 9, 2, 1, ROLE.key)
          if (f % 2) px(c.x + 4 + ((f * 3) % 6), c.y + 6 + (tick % 3), 1, 1, ROLE.body)
        } else if (f % 6 < 3) px(c.x + 3, c.y + 7, 6, 1, ROLE.body)
        px(c.x + 1, c.y + 12, 10, 3, ROLE.edge); px(c.x + 3, c.y + 11, 1, 2, ROLE.prose); px(c.x + 6, c.y + 13, 1, 1, ROLE.alarm); px(c.x + 8, c.y + 13, 1, 1, ROLE.key)
        const best = highs[i]
        sc.hits.push({ x: c.x, y: c.y, w: c.w, h: c.h, tip: `the arcade${best ? ` - best ${best.score} by ${best.name}` : ""} - click to play`, act: { kind: "arcade" } })
      }))
      sc.item(tank.y + tank.h, () => {
        const water = tint(ROLE.key, ROLE.ground, 0.35), glass = tint(ROLE.prose, ROLE.ground, 0.6)
        px(tank.x, tank.y + 18, tank.w, 6, ROLE.structure); px(tank.x + 2, tank.y + 23, 2, 1, ROLE.borderInactive)
        px(tank.x, tank.y, tank.w, 18, glass); px(tank.x + 1, tank.y + 2, tank.w - 2, 15, water); px(tank.x, tank.y, tank.w, 1, ROLE.inactive)
        px(tank.x + 1, tank.y + 15, tank.w - 2, 2, tint(ROLE.body, ROLE.ground, 0.5))
        for (const [wx, h] of [[4, 7], [9, 5], [23, 8]] as const) for (let j = 0; j < h; j++) px(tank.x + wx + ((j + f) % 4 === 0 ? 1 : 0), tank.y + 14 - j, 1, 1, ROLE.live)
        const feeding = sim.at("aquarium").length > 0 && tick % 300 < 50
        if (feeding) for (let k = 0; k < 4; k++) px(tank.x + 10 + k * 3, tank.y + 3 + ((tick + k * 5) % 10), 1, 1, ROLE.body)
        ;[ROLE.alarm, ROLE.body, ROLE.attention].forEach((col, i) => {
          const lap = 22, s = Math.floor(tick / (2 + i)) + i * 7, p = s % (2 * lap), x = p < lap ? p : 2 * lap - p
          const fw = fishWatch(z), nina = sim.cat.x === fw.x && sim.cat.y === fw.y
          const fx = nina ? tank.x + 10 + i * 3 + Math.round(Math.sin((tick + i * 15) / 7) * 2) : tank.x + 2 + x
          const fy = feeding ? tank.y + 4 + i : nina ? tank.y + 9 + i * 2 : tank.y + 5 + i * 3, right = nina ? i % 2 === 0 : p < lap
          px(fx, fy, 3, 2, col); px(right ? fx - 1 : fx + 3, fy + (f % 2), 1, 1, col)
        })
        for (let k = 0; k < 2; k++) px(tank.x + 6 + k * 14, tank.y + 14 - ((tick + k * 9) % 12), 1, 1, ROLE.prose)
      })
      sc.item(foos.y + foos.h, () => {
        px(foos.x, foos.y, foos.w, foos.h - 4, ROLE.structure); px(foos.x + 2, foos.y + 1, foos.w - 4, 6, tint(ROLE.live, ROLE.ground, 0.45))
        px(foos.x + 3, foos.y + 8, 2, 4, ROLE.structure); px(foos.x + foos.w - 5, foos.y + 8, 2, 4, ROLE.structure)
        const on = sim.at("foosball").length === 2
        for (let r = 0; r < 4; r++) {
          const rx = foos.x + 5 + r * 5, dy = on ? ((tick + r * 3) % 4) - 2 : 0
          px(rx, foos.y - 1, 1, 9, ROLE.inactive)
          for (const my of [2, 5]) px(rx, foos.y + my + dy, 1, 1, r % 2 ? ROLE.alarm : ROLE.key)
        }
        if (on) px(foos.x + 3 + ((tick * 3) % (foos.w - 6)), foos.y + 3 + (tick % 2), 1, 1, ROLE.prose)
      })
      sc.item(pool.y + pool.h, () => {
        px(pool.x, pool.y, pool.w, pool.h, ROLE.structure); px(pool.x + 2, pool.y + 2, pool.w - 4, pool.h - 4, tint(ROLE.live, ROLE.ground, 0.4))
        for (const [dx, dy] of [[1, 1], [pool.w / 2 - 1, 1], [pool.w - 3, 1], [1, pool.h - 3], [pool.w / 2 - 1, pool.h - 3], [pool.w - 3, pool.h - 3]] as const) px(pool.x + dx, pool.y + dy, 2, 2, ROLE.fieldInk)
        px(pool.x + 3, pool.y + pool.h, 2, 3, ROLE.structure); px(pool.x + pool.w - 5, pool.y + pool.h, 2, 3, ROLE.structure)
        const colours = [ROLE.body, ROLE.alarm, ROLE.key, ROLE.assistant, ROLE.attention, ROLE.edge]
        if (sim.at("pool").length === 2) {
          const shot = tick % 60, tt = Math.min(1, shot / 20)
          const cue = { x: pool.x + 6 + Math.round(tt * 10), y: pool.y + 6 - Math.round(tt * 2) }
          if (shot < 4) px(cue.x - 7 + shot, cue.y, 6, 1, ROLE.borderInactive)
          px(cue.x, cue.y, 1, 1, ROLE.prose)
          colours.forEach((c, k) => {
            if ((tick >> 6) % 7 === k && shot > 40) return
            const bx = pool.x + 14 + ((k * 5 + (shot > 20 ? Math.round((shot - 20) / 8) * (k % 2 ? 1 : -1) : 0) + 20) % 8), by = pool.y + 3 + ((k * 3) % 6)
            px(bx, by, 1, 1, c)
          })
        } else {
          colours.forEach((c, k) => { const row = k < 1 ? 0 : k < 3 ? 1 : 2, col = k < 1 ? 0 : k < 3 ? k - 1 : k - 3; px(pool.x + 16 + row * 2, pool.y + 5 - row + col * 2, 1, 1, c) })
          px(pool.x + 6, pool.y + 6, 1, 1, ROLE.prose)
        }
      })
    },
    step(tick, at, actors) {
      const playing = new Set<string>()
      for (const x of at("arcade")) {
        const cab = cabinets.findIndex((c) => Math.abs(c.x + 6 - x.x) < 3)
        if (cab < 0) continue
        playing.add(x.seat.agent)
        const run = runs.get(x.seat.agent) ?? { cab, score: 0 }
        if (tick % 4 === 0) run.score += 10 * Math.floor(Math.random() * 6)
        runs.set(x.seat.agent, run)
      }
      for (const [who, run] of runs) {
        if (playing.has(who)) continue
        runs.delete(who)
        if (run.score <= (highs[run.cab]?.score ?? 0)) continue
        highs[run.cab] = { name: who, score: run.score }
        fanfare = tick + 40
        const x = actors.get(who)
        if (x) { x.emote = "!"; x.emoteUntil = tick + 30 }
      }
    },
    highScores() { return highs },
  }
}
