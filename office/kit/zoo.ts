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
  // Gary's dumpster: the lid shut with his eyes glowing in the gap, then propped open
  dumpster: [
    { rows: ["llllllllllll", "kaakkkkkkaak", "ssssssssssss", "ssssssssssss", "ssssssssssss", "s..........s"], map: { l: ROLE.prose, k: ROLE.edge, a: ROLE.attention, s: ROLE.structure } },
    { rows: ["......llllll", "kaakkllllll.", "ssssssssssss", "ssssssssssss", "ssssssssssss", "s..........s"], map: { l: ROLE.prose, k: ROLE.edge, a: ROLE.attention, s: ROLE.structure } },
  ],
  // the gremlin: a trash-can-lid crown, glowing eyes, a banana-peel cape
  gary: [
    { rows: ["lllll", ".sss.", "sasas", ".sss.", "yssys", "yssy.", ".s.s."], map: { l: ROLE.prose, s: ROLE.structure, a: ROLE.attention, y: ROLE.body } },
    { rows: ["lllll", ".sss.", "sasas", ".sss.", "yssys", ".ssy.", "s...s"], map: { l: ROLE.prose, s: ROLE.structure, a: ROLE.attention, y: ROLE.body } },
  ],
  bone: [
    { rows: ["ww...ww", "wwwwwww", "ww...ww"], map: { w: ROLE.prose } },
    { rows: ["...ww.w", "wwwwwww", "w.ww..."], map: { w: ROLE.prose } },
  ],
  sandwich: [{ rows: ["bbbb", "tttt", "bbbb"], map: { b: ROLE.body, t: ROLE.alarm } }],
  sock: [{ rows: ["ww..", "ww..", "wwww"], map: { w: ROLE.prose } }],
  stars: [
    { rows: ["a.a.a", ".a.a."], map: { a: ROLE.key } },
    { rows: [".a.a.", "a.a.a"], map: { a: ROLE.key } },
  ],
}

/** Gary's words: where they print and how big */
const SHOUTS: Partial<Record<PropKind, { size: number; ink: string }>> = {
  shout: { size: 16, ink: ROLE.alarm },
  mutter: { size: 8, ink: ROLE.alarm },
  cackle: { size: 10, ink: ROLE.attention },
}

/** a prop with its feet at (x, y); `flip` mirrors it to face left */
export function drawProp(sc: Scene, p: Prop) {
  const said = SHOUTS[p.kind]
  if (said && p.text) return void sc.overhead.push(() => sc.text(p.text!, p.x, p.y, said.ink, said.size, "center", true))
  const frames = SPRITES[p.kind]
  if (!frames) return
  const s = frames[(p.step ?? 0) % frames.length]!
  const rows = p.flip ? s.rows.map((r) => [...r].reverse().join("")) : s.rows
  if (p.kind === "candle") sc.cv.glow(p.x - 10, p.y - 8, 20, 10, ROLE.body, 0.35)
  sc.item(p.y + 0.5, () => sc.blit(rows, p.x - (rows[0]!.length >> 1), p.y - rows.length, s.map))
}
