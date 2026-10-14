// Uqbar's life in the room while its session is idle (docs/plans/2026-10-08-uqbar-design.md §6): one
// errand at a time — it flies somewhere, lingers, does its one thing, says its line, and flies back
// to rest. An encyclopedia's voice: dry, cross-referencing, a little grand, never about the work.
import type { Pt } from "./uqbar"

export type ErrandKind = "shoulder" | "cork" | "shelf" | "mirror" | "nap" | "nina" | "argos" | "window" | "tv" | "clock" | "lap" | "erratum"
/** `path` the waypoints still to fly; `dwell` ticks to linger once there; `arrived` the tick it got there; `follow` keeps the last one on someone who moves */
export type Errand = { kind: ErrandKind; path: Pt[]; dwell: number; arrived: number | null; name?: string; follow?: () => Pt }

/** what it says, by occasion; `{name}` is whoever it is about */
export const UQBAR = {
  wake: ["Volume XLVI, at your service.", "I was not on the shelf. I was between editions.", "Reopened."],
  shoulder: ["See also: {name}.", "[citation needed]", "Cf. the previous commit.", "{name} writes as though the bug were real.", "This paragraph contradicts an earlier edition.", "A footnote, {name}: it compiles in Tlön."],
  cork: ["Annotated.", "Marginalia: see verso.", "A footnote longer than the note.", "Someone has to keep the index."],
  shelf: ["Restored to its proper place.", "Volume XLV was leaning again.", "The shelf has one book too many. It is me."],
  mirror: ["Mirrors are abominable: they multiply the number of men.", "Not the mirror.", "I do not care for that copy of me."],
  nap: ["zzz", "…the index is dreaming…", "zzz… Orbis… Tertius…"],
  nina: ["Feline, attend.", "A cat is a footnote that bites.", "Come, then. Swat the encyclopedia."],
  argos: ["Argos. Shall I read you the Odyssey again?", "He remembers the last chapter better than I do.", "Good dog. Good poet."],
  window: ["Weather in Tlön: idealist, with scattered nouns.", "The sky is a hypothesis.", "In Tlön there is no word for that cloud. There are eleven adjectives."],
  tv: ["Another channel, another heresiarch.", "This programme is a forgery.", "I have read the book. The book was better. I am the book."],
  clock: ["The hour, in Uqbar too.", "Time, the Tlönists say, is a series of mental states. This one is {name}.", "{name}. Noted in the margin."],
  lap: ["Revised edition!", "Corrigenda absorbed.", "Now in print."],
  erratum: ["Erratum.", "A correction will follow.", "That was not in the first printing."],
  lonely: ["This office does not appear in the atlas.", "Of Uqbar, only this article remains."],
} as const satisfies Record<string, readonly string[]>
export type Occasion = keyof typeof UQBAR

/** the idle errands it picks among (the rest are reactions); a nap only after dark, the cat and dog only when they are about */
export const PASTIMES: ErrandKind[] = ["shoulder", "cork", "shelf", "mirror", "nina", "argos", "window", "tv"]
/** ticks between idle errands (100 ms each): a minute to two and a half */
export const REST = { min: 600, spread: 900 }

/** the next idle errand for a `roll` in [0, 1): never the last one, a nap at night, nothing that needs someone who isn't there */
export function pickErrand(roll: number, last: ErrandKind | null, can: { dark: boolean; working: boolean; cat: boolean; dog: boolean }): ErrandKind {
  const ok = [...PASTIMES, ...(can.dark ? (["nap", "nap"] as ErrandKind[]) : [])].filter(
    (k) => k !== last && (k !== "shoulder" || can.working) && (k !== "nina" || can.cat) && (k !== "argos" || can.dog),
  )
  return ok[Math.floor(roll * ok.length) % ok.length] ?? "cork"
}

/** how long it lingers at each errand's end, in ticks */
export const DWELL: Record<ErrandKind, number> = { shoulder: 140, cork: 90, shelf: 60, mirror: 12, nap: 500, nina: 70, argos: 160, window: 110, tv: 100, clock: 50, lap: 0, erratum: 40 }

/** the lap of honour on a landing: the room's four corners under the back wall and over the hallway, and back */
export const lapOf = (w: number, top: number, bottom: number): Pt[] => [
  { x: w - 30, y: top }, { x: w - 30, y: bottom }, { x: 20, y: bottom }, { x: 20, y: top }, { x: w / 2, y: top },
]

/** the errand's hover-tip line: what the book is up to */
export function doing(e: Errand | null): string | null {
  if (!e) return null
  const n = e.name ?? "someone"
  return {
    shoulder: `reading over ${n}'s shoulder`, cork: "annotating the corkboard", shelf: "tidying the shelf", mirror: "avoiding the mirror",
    nap: "napping on your desk", nina: "baiting Nina", argos: "reading the Odyssey to Argos", window: "looking out at the weather",
    tv: "reviewing the television", clock: "noting the hour", lap: "a lap of honour", erratum: "issuing an erratum",
  }[e.kind]
}
