// RGBA → PNG, the smallest encoder that works: one IDAT, no filtering. The kitty image goes over
// as PNG because ghostty (1.x) crashes inflating a large zlib-compressed raw image (o=z).
import { deflateSync } from "node:zlib"

const TABLE = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0 })
function crc(b: Uint8Array) { let c = 0xffffffff; for (const x of b) c = TABLE[(c ^ x) & 255]! ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0 }
function chunk(type: string, data: Uint8Array) {
  const out = new Uint8Array(12 + data.length), dv = new DataView(out.buffer)
  dv.setUint32(0, data.length); out.set(new TextEncoder().encode(type), 4); out.set(data, 8)
  dv.setUint32(8 + data.length, crc(out.subarray(4, 8 + data.length)))
  return out
}
export function png(w: number, h: number, rgba: Uint8Array): Buffer {
  const ihdr = new Uint8Array(13), dv = new DataView(ihdr.buffer)
  dv.setUint32(0, w); dv.setUint32(4, h); ihdr.set([8, 6, 0, 0, 0], 8)
  const raw = new Uint8Array((w * 4 + 1) * h)
  for (let y = 0; y < h; y++) raw.set(rgba.subarray(y * w * 4, (y + 1) * w * 4), y * (w * 4 + 1) + 1)
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", deflateSync(raw, { level: 1 })), chunk("IEND", new Uint8Array())])
}
