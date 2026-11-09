import { STATE_GLYPH, type CardState } from "../kit/crew"
import { ROLE } from "../kit/palette"
import { type Seg } from "./term"
import { type Mode } from "./state"

export const DETAIL = 14 // the detail pane's rows, title included: fixed, so nothing below the room moves

export const cardKey = (m: Mode) => JSON.stringify({ ...m, from: undefined })

export const tabLabel = (t: string) => (t === "all" ? "everyone" : t)

export const tidSeg = (id: number): Seg => ({ s: `#${id} `, fg: ROLE.key })

export const oneLine = (t: string) => t.replace(/\s+/g, " ")

/** step a required field forward through its catalogue, wrapping */
export function cycleVal<T>(values: readonly T[], cur: T): T { const i = values.indexOf(cur); return values[(i + 1) % values.length]! }

/** step an optional field forward through its catalogue, with undefined ("default"/"none") as one more stop */
export function cycleOpt<T>(values: readonly T[], cur: T | undefined): T | undefined {
  const all: (T | undefined)[] = [undefined, ...values], i = all.indexOf(cur)
  return all[(i + 1) % all.length]
}

export const dim = (s: string): Seg => ({ s, fg: ROLE.inactive }), plain = (s: string): Seg => ({ s, fg: ROLE.prose })

export const key = (s: string): Seg => ({ s, fg: ROLE.key }), pink = (s: string): Seg => ({ s, fg: ROLE.attention })

export const live = (s: string): Seg => ({ s, fg: ROLE.live })

export const cols = () => process.stdout.columns ?? 80

/** the detail pane's text width: the terminal's, less the actions column when there is room for it */
export const paneW = () => (cols() >= 80 ? cols() - ACTIONS_W - 1 : cols())

/** a card state's glyph: ▶ at a desk, ⏸ parked, ◇ idle, ⚑ needs you */
export const stateSeg = (st: CardState): Seg => ({ s: `${STATE_GLYPH[st.kind]} `, fg: st.kind === "running" ? ROLE.live : st.kind === "needs" ? ROLE.attention : ROLE.inactive, bold: true })

export const ago = (at: string) => {
  const s = Math.max(0, (Date.now() - new Date(at).getTime()) / 1000)
  return s < 60 ? "now" : s < 3600 ? `${Math.floor(s / 60)}m` : s < 86400 ? `${Math.floor(s / 3600)}h` : `${Math.floor(s / 86400)}d`
}

export const stamp = (at: string) => {
  const d = new Date(at), p = (n: number) => String(n).padStart(2, "0")
  return `${d.toDateString().slice(4, 10)} ${p(d.getHours())}:${p(d.getMinutes())}`
}

export const runGlyph = (r: { status: string }): Seg => (r.status === "ok" ? { s: "✓", fg: ROLE.live } : r.status === "failed" ? { s: "✗", fg: ROLE.alarm } : r.status === "interrupted" ? { s: "⊘", fg: ROLE.inactive } : { s: "…", fg: ROLE.key })

export const pick = <T,>(xs: T[], i: number) => (i >= 0 ? xs[i] : undefined)

export const ACTIONS_W = 34

export const keyName = (k: string) => ({ space: "␣", enter: "⏎", right: "→", left: "←" })[k] ?? k
