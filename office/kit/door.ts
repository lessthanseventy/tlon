// The front door (toy design §5): who comes by, when, and what a snapshot says arrived. Pure — sim.ts runs
// the visit, rooms/wide.ts draws the door, tui/main.ts feeds it snapshots.
import { mailbox } from "./mailbox"
import type { Agents } from "./types"

export type VisitorKind = "carrier" | "pizza" | "cookies" | "tourist" | "trick" | "carol"
/** the first scheduled ring; later ones are RING_MIN + a draw of RING_SPAN (15 to 45 minutes at 100 ms) */
export const RING_FIRST = 6_000, RING_MIN = 9_000, RING_SPAN = 18_000
/** the hours a scheduled ring may come (a bell asked for by a cut or a key rings whenever) */
export const OPEN_FROM = 8, OPEN_TO = 18
/** ticks: how long the bell rattles, how long a visitor waits for someone to come, how long they stay, how long pizza pulls the crew to the kitchen */
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
