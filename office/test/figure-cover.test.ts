// Furniture labels sit behind the people and pets drawn in front of them; balloons and brackets stay on top.
import { describe, expect, test } from "bun:test"
import { Scene } from "../kit/draw"
import { geometry, inkInto, textLayer } from "../tui/paint"

const W = 40, H = 20, K = 2
/** a scene with a plate across row 10 and a 3×5 figure stood over its middle */
function scene() {
  const sc = new Scene(W, H, 0)
  sc.px(0, 0, W, H, "#202020")
  sc.text("lonnrot", 20, 12, "#ffffff", 10)
  sc.figure(["###", "###", "###", "###", "###"], 19, 6, { "#": "#ff0000" })
  return sc.finish()
}
const at = (rgba: Uint8Array, w: number, x: number, y: number) => [...rgba.subarray((y * w + x) * 4, (y * w + x) * 4 + 3)]

describe("figures draw over furniture labels", () => {
  test("Scene.figure marks the sprite's pixels", () => {
    const fr = scene()
    expect(fr.cover![6 * W + 20]).toBe(1)
    expect(fr.cover![5 * W + 20]).toBe(0)
  })
  test("kitty: a label's pixels under the figure stay the figure's; the rest of the plate prints", () => {
    const fr = scene()
    const big = new Uint8Array(W * K * H * K * 4)
    for (let y = 0; y < H * K; y++) for (let x = 0; x < W * K; x++) big.set(fr.rgba.subarray((Math.floor(y / K) * W + Math.floor(x / K)) * 4, (Math.floor(y / K) * W + Math.floor(x / K)) * 4 + 4), (y * W * K + x) * 4)
    const plain = big.slice()
    inkInto(plain, W * K, H * K, fr.ink, K, 1)
    inkInto(big, W * K, H * K, fr.ink, K, 1, undefined, undefined, fr.cover)
    let lit = 0, hidden = 0
    for (let y = 0; y < H * K; y++) for (let x = 0; x < W * K; x++) {
      const was = at(plain, W * K, x, y), now = at(big, W * K, x, y)
      if (fr.cover![Math.floor(y / K) * W + Math.floor(x / K)]) { expect(now).toEqual([255, 0, 0]); if (was.join() !== "255,0,0") hidden++ }
      else if (now.join() === "255,255,255") lit++
    }
    expect(hidden).toBeGreaterThan(0)
    expect(lit).toBeGreaterThan(0)
  })
  test("half blocks: the cells under the figure keep their art", () => {
    const fr = scene()
    const g = geometry(W, H, W, H, 0, null, false)
    const txt = (r: string) => r.replace(/\x1b\[[0-9;]*m/g, "")
    const covered = textLayer(fr, g).map(txt), free = textLayer({ ...fr, cover: undefined }, g).map(txt)
    const row = Math.floor((12 * g.k - 0.01) / g.ch)
    expect(free[row]).toContain("lonnrot")
    expect(covered[row]).not.toContain("lonnrot")
    expect(covered[row]).toContain("lo"); expect(covered[row]).toContain("ot")
  })
  test("`over` text is not hidden", () => {
    const sc = new Scene(W, H, 0)
    sc.text("z", 20, 8, "#ffffff", 10, "center", true)
    sc.figure(["###", "###", "###"], 19, 4, { "#": "#ff0000" })
    expect(sc.finish().ink[0]).toMatchObject({ over: true })
  })
})
