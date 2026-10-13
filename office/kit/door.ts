// The front door (toy design §5): who comes by, when, and what a snapshot says arrived. Pure — sim.ts runs
// the visit, rooms/wide.ts draws the door, tui/main.ts feeds it snapshots.
import type { Scene } from "./draw"
import { mailbox } from "./mailbox"
import { ROLE } from "./palette"
import type { Agents } from "./types"

export type VisitorKind = "carrier" | "pizza" | "cookies" | "tourist" | "trick" | "carol"
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
}
/** a visitor standing with their feet at (x, y) */
export function drawVisitor(sc: Scene, x: number, y: number, kind: VisitorKind) {
  const k = KIT[kind], rows = BASE.map((r, i) => k.rows[i] ?? r)
  sc.item(y + 0.5, () => sc.blit(rows, x - 3, y - 10, { h: ROLE.structure, s: ROLE.body, b: k.body, l: ROLE.inactive, p: ROLE.prose }))
}
