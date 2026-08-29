// The adapters-lspd wire protocol: length-prefixed JSON over a Unix socket, one message per
// tool op. A 4-byte big-endian length prefix + the UTF-8 JSON body — unambiguous framing
// (no escaping issues, unlike newline-delimited). Pure + unit-tested: the daemon and the
// pi shim both speak it, so this codec is the one seam that must not drift.

import type { LineRange } from "./impact.ts";

export interface LspdRequest {
  id: number;
  method: "hover" | "definition" | "references" | "symbols" | "diagnostics" | "impact";
  // `ranges` is additive and used only by `impact` (the changed line spans of `path`); every
  // other method reads `path`/`line`/`col` and ignores it, so the seam stays backward-compatible.
  params: { path: string; line?: number; col?: number; ranges?: LineRange[] };
}

export type LspdResponse =
  | { id: number; ok: true; text: string }
  | { id: number; ok: false; error: string };

export function encode(msg: LspdRequest | LspdResponse): Buffer {
  const body = Buffer.from(JSON.stringify(msg), "utf-8");
  const len = Buffer.alloc(4);
  len.writeUInt32BE(body.length, 0);
  return Buffer.concat([len, body]);
}

// Any frame claiming to be bigger than this is a corrupt prefix (or a client speaking the wrong
// protocol), not a real message — without the cap the decoder would buffer toward 4GiB waiting
// for a length that never arrives.
const MAX_FRAME_BYTES = 16 * 1024 * 1024;

// Accumulate chunks and yield complete messages. Handles a message split across chunks and
// several messages arriving in one chunk — the two real-world cases on a streamed socket.
// Throws on a corrupt frame (oversized length or non-JSON body) — the caller drops that
// CONNECTION; the shared daemon must never die over one bad client.
export class Decoder {
  #buf: Buffer = Buffer.alloc(0);

  push(chunk: Buffer): unknown[] {
    this.#buf = this.#buf.length === 0 ? chunk : Buffer.concat([this.#buf, chunk]);
    const out: unknown[] = [];
    for (;;) {
      if (this.#buf.length < 4) return out;
      const len = this.#buf.readUInt32BE(0);
      if (len > MAX_FRAME_BYTES) throw new Error(`lspd codec: frame length ${len} exceeds ${MAX_FRAME_BYTES}`);
      if (this.#buf.length < 4 + len) return out;
      const body = this.#buf.subarray(4, 4 + len).toString("utf-8");
      this.#buf = this.#buf.subarray(4 + len);
      out.push(JSON.parse(body));
    }
  }
}
