// The event scenes' small sprites: blit grids like `drawVisitor` (kit/door.ts).
import type { Scene } from "./draw"
import type { Prop, PropKind } from "./events"
import { ROLE } from "./palette"

type Sprite = { rows: string[]; map: Record<string, string> }
const SPRITES: Partial<Record<PropKind, Sprite[]>> = {
  duck: [
    { rows: ["..yy....", ".yyyy.o.", "yyyyyooo", ".yyyyy..", "..oo.oo."], map: { y: ROLE.body, o: ROLE.alarm } },
    { rows: ["..yy....", ".yyyy.o.", "yyyyyooo", ".yyyyy..", "...oo.o."], map: { y: ROLE.body, o: ROLE.alarm } },
  ],
  candle: [
    { rows: ["..y", "..o", ".kkk"], map: { y: ROLE.body, o: ROLE.alarm, k: ROLE.prose } },
    { rows: [".y.", "..o", ".kkk"], map: { y: ROLE.body, o: ROLE.alarm, k: ROLE.prose } },
  ],
  streak: [{ rows: ["..o", "..o", ".oo", "oo."], map: { o: ROLE.body } }],
  puff: [{ rows: ["..p..", ".ppp.", "ppppp"], map: { p: ROLE.prose } }],
  crater: [{ rows: [".....", ".kkk.", "kkkkk"], map: { k: ROLE.structure } }],
}

/** a prop with its feet at (x, y); `flip` mirrors it to face left */
export function drawProp(sc: Scene, p: Prop) {
  const frames = SPRITES[p.kind]
  if (!frames) return
  const s = frames[(p.step ?? 0) % frames.length]!
  const rows = p.flip ? s.rows.map((r) => [...r].reverse().join("")) : s.rows
  if (p.kind === "candle") sc.cv.glow(p.x - 10, p.y - 8, 20, 10, ROLE.body, 0.35)
  sc.item(p.y + 0.5, () => sc.blit(rows, p.x - (rows[0]!.length >> 1), p.y - rows.length, s.map))
}
