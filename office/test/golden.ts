// The wide room's golden frames: one SHA-256 per width of a fixed, seeded scene. wide.test.ts
// checks them against golden.json; run as a script (`mise run office:golden`) it rewrites that
// file. Kept out of the test so a landing can re-hash after a rebase instead of conflicting on it.
import { createHash } from "node:crypto"
import { viewOf } from "../kit/crew"
import { EMPTY, type Agents } from "../kit/types"
import { WideRoom } from "../rooms/wide"

export const GOLDEN = new URL("./golden.json", import.meta.url).pathname

export const measure = (s: string) => s.length * 2
export const focus = { picked: null, armed: null, person: null }

/** run `f` with Math.random seeded (mulberry32), so a test of the room's chance is the same every run */
export function seeded<T>(seed: number, f: () => T): T {
  const real = Math.random
  let a = seed >>> 0
  Math.random = () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296 }
  try { return f() } finally { Math.random = real }
}

export function office(grunts: number): Agents {
  const names = ["tertius", "hronir", ...Array.from({ length: grunts }, (_, i) => `w${i}`)]
  return {
    ...EMPTY, ok: true,
    workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "surveyor", meta: true, read_only: true, model: "" }, { name: "builder", meta: false, read_only: false, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: i === 0 ? "surveyor" : "builder", lead: i === 1, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `thread ${i}`, stage: i === 1 ? "build" : null, awaiting: null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: true, thinking: true, workspace_id: 1 })),
    notes: [{ id: 1, author: "hronir", body: "a note", workspace_id: 1, at: new Date(0).toISOString() }],
  }
}

export const WIDTHS = [540, 560, 640, 696, 900]

/** each width's frame hash, `{"540": "<sha256>", …}` */
export function frameHashes(): Record<string, string> {
  return seeded(1, () => Object.fromEntries(WIDTHS.map((w) => {
    const room = new WideRoom(w), a = viewOf(office(6), 1)
    // a fixed hour for the steps, as for the render: who lounges where follows the clock
    ;(room as unknown as { hour: () => number }).hour = () => 16
    for (let i = 0; i < 300; i++) room.step(a)
    const fr = room.render(a, focus, measure, new Date(2026, 9, 5, 21, 0))
    return [String(w), createHash("sha256").update(Buffer.from(fr.rgba)).digest("hex")]
  })))
}

if (import.meta.main) await Bun.write(GOLDEN, JSON.stringify(frameHashes(), null, 2) + "\n")
