import { expect, spyOn, test } from "bun:test"
import { PNG } from "pngjs"
import type { Frame } from "../kit/canvas"
import * as pngmod from "../tui/png"
import { inkInto, kittyImage } from "../tui/paint"

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

test("encode cost of one frame", () => {
  const fr = frame(2), w = W * 3, h = H * 3, big = new Uint8Array(w * h * 4)
  const src = new Uint32Array(fr.rgba.buffer), dst = new Uint32Array(big.buffer)
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) dst[y * w + x] = src[Math.floor(y / 3) * W + Math.floor(x / 3)]!
  pngmod.png(w, h, big)
  const t0 = performance.now()
  let bytes = 0
  for (let i = 0; i < 10; i++) bytes = pngmod.png(w, h, big).length
  console.log(`png-bench: ${((performance.now() - t0) / 10).toFixed(1)} ms, ${bytes} bytes per ${w}x${h} frame`)
})

test("the encoded PNG decodes to the same pixels", () => {
  const w = 37, h = 11, rgba = new Uint8Array(w * h * 4).map((_, i) => (i * 7 + (i >> 5) * 13) & 255)
  const back = PNG.sync.read(pngmod.png(w, h, rgba))
  expect([back.width, back.height]).toEqual([w, h])
  expect(new Uint8Array(back.data)).toEqual(rgba)
})

test("labels: inking 300 labels over unchanged art", () => {
  const w = W * 3, h = H * 3, art = new Uint8Array(w * h * 4)
  for (let p = 0; p < w * h; p++) { art[p * 4] = (p >> 7) & 255; art[p * 4 + 1] = (p >> 9) & 255; art[p * 4 + 2] = 90; art[p * 4 + 3] = 255 }
  const ink: Frame["ink"] = Array.from({ length: 300 }, (_, n) => ({ t: "text" as const, s: `label ${n}`, x: 5 + (n % 6) * 50, y: 12 + Math.floor(n / 6) * 3.5, color: n % 2 ? "#ffffff" : "#334455", size: 10, align: "left" as const }))
  let best = Infinity
  for (let i = 0; i < 30; i++) { const big = art.slice(), t0 = performance.now(); inkInto(big, w, h, ink, 3, 1); best = Math.min(best, performance.now() - t0) }
  console.log(`label-bench: ${best.toFixed(1)} ms per frame (best of 30), 300 labels`)
})
