import { expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { ROLE } from "../kit/palette"
import { corner, WideRoom, zones } from "../rooms/wide"
import { focus, measure, office, seeded } from "./golden"

// The operator saw the balls move with nobody hitting them: the players stood at the table and the
// only cue was a faint stub. A game in play shows its shooter's cue, drawn back, then striking.
test("a pool shot is in someone's hands: the cue runs from the shooter to the ball while aiming, and is put down while the balls roll", () => seeded(11, () => {
  const o = office(10)
  o.roster = o.roster.map((r, i) => (i > 2 ? { ...r, thinking: false, warm: false } : r))
  const a = viewOf(o, 1), r: any = new WideRoom(696)
  r.hour = () => 12
  const pool = corner(zones(696)).pool
  for (let i = 0; r.peopleAt("pool").length < 2 && i < 40_000; i++) r.step(a)
  expect(r.peopleAt("pool").length).toBe(2)

  const hex = (fr: any, x: number, y: number) => { const o = (y * fr.width + x) * 4; return "#" + [0, 1, 2].map((k) => fr.rgba[o + k].toString(16).padStart(2, "0")).join("").toUpperCase() }
  const along = (shooter: any, d: number) => {
    const ball = { x: pool.x + 6, y: pool.y + 6 }, dx = shooter.x - ball.x, dy = shooter.y - 7 - ball.y, len = Math.hypot(dx, dy)
    return { x: Math.round(ball.x + (dx / len) * d), y: Math.round(ball.y + (dy / len) * d) }
  }
  while (r.tick % 60 !== 5) r.step(a)
  const shooter = r.peopleAt("pool")[Math.floor(r.tick / 60) % 2]
  const p = along(shooter, 9)
  expect(hex(r.render(a, focus, measure, new Date(2026, 9, 5, 12, 0)), p.x, p.y)).toBe(ROLE.body.toUpperCase())
  while (r.tick % 60 !== 30) r.step(a)
  expect(hex(r.render(a, focus, measure, new Date(2026, 9, 5, 12, 0)), p.x, p.y)).not.toBe(ROLE.body.toUpperCase())
}))
