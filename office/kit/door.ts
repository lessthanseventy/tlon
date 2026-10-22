// The front door (toy design §5): who comes by, when, and what a snapshot says arrived. Pure — sim.ts runs
// the visit, rooms/wide.ts draws the door, tui/main.ts feeds it snapshots.
import type { Scene } from "./draw"
import { mailbox } from "./mailbox"
import type { DataPart, Slot, View } from "./parts"
import { ROLE } from "./palette"
import type { Agents } from "./types"

export type VisitorKind = "carrier" | "pizza" | "cookies" | "tourist" | "trick" | "carol" | "guest"
/** a visitor the server generated (`GET /api/office/toys/:ws`): a name, a seed for their look, what they say at the door */
export type Guest = { name: string; look_seed: string | number; line: string }
/** the server's pooled toys: visitors, puns, and per-seat per-event reaction lines — each empty until generated (`Server.ToyPool`) */
export type Toys = { visitors: Guest[]; puns: string[]; reactions: Record<string, Record<string, string[]>>; parts: DataPart[] }
const PART_SLOTS: readonly unknown[] = ["head", "neck", "hand"]
const rowsOf = (x: unknown): View | null => {
  if (!x || typeof x !== "object") return null
  const v: View = {}
  for (const [k, r] of Object.entries(x)) {
    if (!/^\d+$/.test(k) || typeof r !== "string" || r.length !== 12) return null
    v[Number(k)] = r
  }
  return Object.keys(v).length ? v : null
}
/** a toys payload from an older or newer server, narrowed to what is usable; null when it is neither */
export function toysOf(j: unknown): Toys | null {
  if (!j || typeof j !== "object") return null
  const o = j as Record<string, unknown>
  const strs = (x: unknown): string[] => (Array.isArray(x) ? x.filter((v): v is string => typeof v === "string" && v.trim() !== "") : [])
  const visitors = (Array.isArray(o.visitors) ? o.visitors : []).filter((v): v is Guest => !!v && typeof v === "object" && typeof (v as Guest).name === "string" && typeof (v as Guest).line === "string").map((v) => ({ name: v.name, look_seed: v.look_seed ?? v.name, line: v.line }))
  const reactions: Toys["reactions"] = {}
  if (o.reactions && typeof o.reactions === "object") for (const [seat, evs] of Object.entries(o.reactions)) if (evs && typeof evs === "object") for (const [ev, lines] of Object.entries(evs)) {
    const ok = strs(lines)
    if (ok.length) (reactions[seat] ??= {})[ev] = ok
  }
  const parts = (Array.isArray(o.parts) ? o.parts : []).flatMap((p): DataPart[] => {
    const q = p as Record<string, unknown> | null
    const front = rowsOf(q?.front), side = rowsOf(q?.side), back = rowsOf(q?.back)
    const ok = q && typeof q.id === "string" && q.id.startsWith("gen:") && typeof q.day === "string" && PART_SLOTS.includes(q.slot)
    return ok && front && side && back ? [{ id: q.id as string, day: q.day as string, slot: q.slot as Slot, front, side, back }] : []
  })
  return { visitors, puns: strs(o.puns), reactions, parts }
}
/** the first scheduled ring; later ones are RING_MIN + a draw of RING_SPAN (15 to 45 minutes at 100 ms) */
export const RING_FIRST = 6_000, RING_MIN = 9_000, RING_SPAN = 18_000
/** the hours a scheduled ring may come (a bell asked for by a cut or a key rings whenever) */
export const OPEN_FROM = 8, OPEN_TO = 18
/** ticks: how long the bell rattles, how long a visitor waits for someone to start coming (not while the answerer is on the way), how long they stay, how long pizza pulls the crew to the kitchen */
export const BELL = 15, WAIT = 150, STAY = 70, PIZZA_TICKS = 600
/** visitors queued behind the one at the door */
export const QUEUE_MAX = 3

/** what the answerer says when they open it */
export const LINE: Record<VisitorKind, string> = {
  carrier: "Post's here.",
  pizza: "Pizza! The release landed. Kitchen, everyone.",
  cookies: "Cookies! We'll take two boxes.",
  tourist: "Uqbar? No idea, sorry. Try the shelf?",
  trick: "Happy Halloween!",
  carol: "Oh, lovely. Truly.",
  guest: "Hello.",
}

/** a day's own visitor, or null */
export function seasonal(d: Date): VisitorKind | null {
  const m = d.getMonth(), day = d.getDate()
  if (m === 9 && day === 31) return "trick"
  if (m === 11 && day >= 18 && day <= 24) return "carol"
  return null
}

/** a roll in [0, 1) and the day → a visitor; a day's own one takes half the rolls. Never pizza: only a cut brings it. */
export function pickVisitor(roll: number, day: Date): VisitorKind {
  const special = seasonal(day)
  if (special && roll < 0.5) return special
  const r = special ? (roll - 0.5) * 2 : roll
  return (["carrier", "cookies", "tourist"] as const)[Math.min(2, Math.floor(r * 3))]!
}

/** what this refresh brought: a cut is pizza, a fuller mailbox is the carrier. Only between two real snapshots. */
export function arrivals(before: Agents, after: Agents, beforeNeeds: { level: "blocking" | "decide" }[], needs: { level: "blocking" | "decide" }[]): VisitorKind[] {
  if (!before.ok || !after.ok) return []
  const out: VisitorKind[] = []
  if (after.release && before.release?.sha !== after.release.sha) out.push("pizza")
  if (mailbox(needs).total > mailbox(beforeNeeds).total) out.push("carrier")
  return out
}

/** the door at the hall's right end, its foot on row `hall`: shut it is a slab with a bell; open it is a dark gap with the leaf swung back. State is shape, never colour alone. */
export function drawDoor(sc: Scene, x: number, hall: number, open: boolean, ringing: boolean) {
  const px = sc.px.bind(sc), top = hall - 24
  px(x - 1, top - 1, 12, 26, ROLE.structure)
  if (open) { px(x, top, 10, 25, ROLE.ground); px(x, top, 2, 25, ROLE.key) }
  else { px(x, top, 10, 25, ROLE.edge); px(x + 7, hall - 12, 2, 2, ROLE.prose) }
  px(x - 5, hall - 14, 3, 3, ringing && sc.f % 2 ? ROLE.attention : ROLE.inactive)
  if (ringing) { px(x - 7, hall - 15, 1, 5, ROLE.attention); px(x - 8, hall - 16, 1, 7, ROLE.attention) }
  sc.text("EXIT", x + 5, top - 4, ROLE.live, 11)
}

const BASE = ["..hhh..", ".hhhhh.", ".sssss.", ".sssss.", "..bbb..", ".bbbbb.", ".bbbbb.", ".bbbbb.", "..lll..", "..l.l.."]
/** what each visitor changes about the figure: rows replaced, so the silhouettes differ */
const KIT: Record<VisitorKind, { rows: Record<number, string>; body: string }> = {
  carrier: { rows: { 0: ".hhhhh.", 6: "pbbbbb.", 7: "ppbbb.." }, body: ROLE.key },
  pizza: { rows: { 4: "ppppppp", 5: "ppppppp" }, body: ROLE.alarm },
  cookies: { rows: { 0: "h.hhh.h", 6: "bbbbbpp", 7: "bbbbbpp" }, body: ROLE.attention },
  tourist: { rows: { 0: "hhhhhhh", 5: "ppbbbbb", 6: "ppbbbb." }, body: ROLE.live },
  trick: { rows: { 0: "..h.h..", 1: ".hhhhh.", 6: "bbbbbbp", 7: ".bbbbpp" }, body: ROLE.assistant },
  carol: { rows: { 0: ".hhhhh.", 1: "hhhhhhh", 6: "bbbbbp.", 7: "bbbbbp." }, body: ROLE.prose },
  guest: { rows: { 0: "..hhh..", 5: "pbbbbbp" }, body: ROLE.key },
}
/** a visitor standing with their feet at (x, y) */
const GUEST_BODY = [ROLE.key, ROLE.live, ROLE.attention, ROLE.assistant, ROLE.prose]
const GUEST_HEAD = ["..hhh..", ".hhhhh.", "h.hhh.h", "hhhhhhh"]
const seedHash = (seed: string | number) => [...String(seed)].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7)
export function drawVisitor(sc: Scene, x: number, y: number, kind: VisitorKind, seed?: string | number) {
  const k = kind === "guest" && seed !== undefined
    ? { rows: { ...KIT.guest.rows, 0: GUEST_HEAD[(seedHash(seed) >> 3) % GUEST_HEAD.length]! }, body: GUEST_BODY[seedHash(seed) % GUEST_BODY.length]! }
    : KIT[kind]
  const rows = BASE.map((r, i) => k.rows[i] ?? r)
  sc.item(y + 0.5, () => sc.blit(rows, x - 3, y - 10, { h: ROLE.structure, s: ROLE.body, b: k.body, l: ROLE.inactive, p: ROLE.prose }))
}
