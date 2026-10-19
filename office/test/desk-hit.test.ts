import { expect, test } from "bun:test"
import { bossDesk } from "../kit/furniture"
import { viewOf } from "../kit/crew"
import { EMPTY } from "../kit/types"
import { Scene } from "../kit/draw"

test("clicking your own desk's label opens your card, as clicking the desk does", () => {
  const a = viewOf({ ...EMPTY, ok: true }, 1)
  const sc = new Scene(100, 100, 0)
  bossDesk(sc, a, { x: 20, y: 20, w: 40 })
  const fr = sc.finish()
  const label = fr.ink.find((i) => i.t === "text" && i.s === "you")!
  if (label.t !== "text") throw new Error("no label")
  const hit = fr.hits.find((h) => label.x >= h.x && label.x < h.x + h.w && label.y - 1 >= h.y && label.y - 1 < h.y + h.h)
  expect(hit?.act).toEqual({ kind: "boss" })
})
