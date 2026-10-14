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
  van: [{ rows: ["..wwwwwwwwww..", ".wwwwwwwwwwww.", "wwwwwwwwwwwwww", "wzzzwzzzwzzzww", "wwwwwwwwwwwwww", ".kk........kk."], map: { w: ROLE.prose, z: ROLE.alarm, k: ROLE.edge } }],
  monkey: [
    { rows: ["..b..", ".bbb.", "bbbbb", ".b.b.", "b...b"], map: { b: ROLE.structure } },
    { rows: ["..b..", ".bbb.", "bbbbb", ".b.b.", ".b.b."], map: { b: ROLE.structure } },
  ],
  penguin: [
    { rows: ["..k..", ".kkk.", ".kwk.", ".kwk.", ".kkk.", ".o.o."], map: { k: ROLE.edge, w: ROLE.prose, o: ROLE.body } },
    { rows: ["..k..", ".kkk.", ".kwk.", ".kwk.", ".kkk.", "o...o"], map: { k: ROLE.edge, w: ROLE.prose, o: ROLE.body } },
  ],
  goat: [
    { rows: ["g.g....", "ggg....", ".gggggg", ".gggggg", ".g.g.g.", ".g.g.g."], map: { g: ROLE.prose } },
    { rows: ["g.g....", "ggg....", ".gggggg", ".gggggg", "..g.g.g", ".g.g.g."], map: { g: ROLE.prose } },
  ],
  net: [{ rows: ["nnn", "n.n", "nnn", ".n.", ".n."], map: { n: ROLE.key } }],
  streak: [{ rows: ["..o", "..o", ".oo", "oo."], map: { o: ROLE.body } }],
  puff: [{ rows: ["...p...", "..ppp..", ".ppppp.", "ppppppp"], map: { p: ROLE.prose } }],
  crater: [{ rows: [".........", "..kkkkk..", "kkkkkkkkk"], map: { k: ROLE.structure } }],
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
