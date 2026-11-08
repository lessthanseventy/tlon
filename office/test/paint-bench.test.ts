import { expect, spyOn, test } from "bun:test"
import type { Frame } from "../kit/canvas"
import * as pngmod from "../tui/png"
import { kittyImage } from "../tui/paint"

const W = 320, H = 200
function frame(seed: number): Frame {
  const rgba = new Uint8Array(W * H * 4)
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const o = (y * W + x) * 4, tile = ((x >> 3) + (y >> 3) + seed) & 3
    rgba[o] = 40 + tile * 50; rgba[o + 1] = 60 + ((x >> 4) & 1) * 30; rgba[o + 2] = 90 + ((y >> 4) & 1) * 40; rgba[o + 3] = 255
  }
  const ink: Frame["ink"] = [0, 1, 2, 3, 4, 5].map((n) => ({ t: "text" as const, s: `label ${n}`, x: 20 + n * 40, y: 30 + n * 20, color: "#ffffff", size: 10, align: "left" as const }))
  return { rgba, width: W, height: H, ink, hits: [] }
}
const g = { k: 3, cw: 8, ch: 18, col: 0, row: 0, cols: 120, rows: 34, kitty: true, floorW: W, floorH: H }
const vp = { x: 0, y: 0, w: W, h: H }

test("fifty identical frames encode one PNG; a changed frame encodes again", () => {
  const spy = spyOn(pngmod, "png")
  const fr = frame(0)
  const t0 = performance.now()
  for (let i = 0; i < 50; i++) kittyImage({ ...fr, rgba: fr.rgba.slice(), ink: structuredClone(fr.ink) }, g, vp)
  const ms = (performance.now() - t0) / 50
  expect(spy).toHaveBeenCalledTimes(1)
  kittyImage(frame(1), g, vp)
  expect(spy).toHaveBeenCalledTimes(2)
  console.log(`paint-bench: ${ms.toFixed(2)} ms per identical frame`)
  spy.mockRestore()
})
