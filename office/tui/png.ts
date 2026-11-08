// RGBA → PNG, the smallest encoder that works: one IDAT, sub-filtered rows. The kitty image goes over
// as PNG because ghostty (1.3 tip) crashes inflating some zlib-compressed raw images (o=z).
import { deflateSync } from "node:zlib"

const SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10]

/** the chunks of one PNG laid out in a single buffer: length, type, data, crc of type+data */
function assemble(chunks: [string, Uint8Array][]): Buffer {
  const out = Buffer.alloc(SIGNATURE.length + chunks.reduce((n, [, d]) => n + 12 + d.length, 0))
  out.set(SIGNATURE)
  let at = SIGNATURE.length
  for (const [type, data] of chunks) {
    out.writeUInt32BE(data.length, at)
    out.write(type, at + 4, "latin1")
    out.set(data, at + 8)
    out.writeUInt32BE(Bun.hash.crc32(out.subarray(at + 4, at + 8 + data.length)), at + 8 + data.length)
    at += 12 + data.length
  }
  return out
}

export function png(w: number, h: number, rgba: Uint8Array): Buffer {
  const ihdr = new Uint8Array(13), dv = new DataView(ihdr.buffer)
  dv.setUint32(0, w); dv.setUint32(4, h); ihdr.set([8, 6, 0, 0, 0], 8)
  const stride = w * 4, raw = new Uint8Array((stride + 1) * h), px = new Uint32Array(rgba.buffer, rgba.byteOffset, w * h)
  for (let y = 0; y < h; y++) {
    const s = y * stride, d = y * (stride + 1) + 1
    raw[d - 1] = 1
    for (let i = 0; i < Math.min(4, stride); i++) raw[d + i] = rgba[s + i]!
    // sprite art repeats pixels, and `raw` starts zeroed, which is exactly the sub filter of a repeat
    for (let p = y * w + 1, end = y * w + w; p < end; p++) {
      if (px[p] === px[p - 1]) continue
      const i = (p - y * w) * 4
      for (let c = 0; c < 4; c++) raw[d + i + c] = rgba[s + i + c]! - rgba[s + i + c - 4]!
    }
  }
  return assemble([["IHDR", ihdr], ["IDAT", deflateSync(raw, { level: 1 })], ["IEND", new Uint8Array()]])
}
