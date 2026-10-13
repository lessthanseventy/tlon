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
}

/** a prop with its feet at (x, y); `flip` mirrors it to face left */
export function drawProp(sc: Scene, p: Prop) {
  const frames = SPRITES[p.kind]
  if (!frames) return
  const s = frames[(p.step ?? 0) % frames.length]!
  const rows = p.flip ? s.rows.map((r) => [...r].reverse().join("")) : s.rows
  sc.item(p.y + 0.5, () => sc.blit(rows, p.x - (rows[0]!.length >> 1), p.y - rows.length, s.map))
}
