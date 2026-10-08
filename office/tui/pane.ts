// The detail pane's layout, apart from drawing it: which rows a pane of `room` lines shows (and how
// many it hides above and below, each count costing a line of its own), and the foot's key hints
// wrapped to the terminal's width.

/** the rows shown: `count` from `first`, with `above` and `below` left out of view */
export type Window = { first: number; count: number; above: number; below: number }
/** a key and what it does, as the foot lists it */
export type Hint = { key: string; label: string }

const clamp = (x: number, lo: number, hi: number) => Math.max(lo, Math.min(x, hi))

/** `n` rows in `room` lines, kept centred on the selection `sel` once they overflow */
export function follow(n: number, sel: number, room: number): Window {
  if (n <= room) return { first: 0, count: n, above: 0, below: 0 }
  if (room < 3) { const first = clamp(sel, 0, n - room); return { first, count: room, above: 0, below: 0 } }
  const edge = room - 1
  let first = clamp(sel - Math.floor(edge / 2), 0, n - edge), count = edge
  if (first > 0 && first < n - edge) {
    count = room - 2
    first = clamp(sel - Math.floor(count / 2), 1, n - count - 1)
  }
  return { first, count, above: first, below: n - first - count }
}

/** `n` rows in `room` lines, scrolled down by `by` (clamped so the last page ends on the last row) */
export function offset(n: number, room: number, by: number): Window {
  if (n <= room) return { first: 0, count: n, above: 0, below: 0 }
  if (room < 3) { const first = clamp(by, 0, n - room); return { first, count: room, above: 0, below: 0 } }
  const first = clamp(by, 0, n - (room - 1))
  let count = room - (first > 0 ? 1 : 0)
  if (first + count < n) count -= 1
  return { first, count, above: first, below: n - first - count }
}

const SEP = 3 // " · "
const span = (h: Hint) => [...h.key].length + 1 + [...h.label].length

/** the hints packed into lines of `width`, at most `max` of them; what does not fit becomes "+N more" */
export function footLines(hints: Hint[], width: number, max: number): Hint[][] {
  const lines: Hint[][] = []
  let used = 0
  for (const h of hints) {
    const cur = lines[lines.length - 1]
    if (cur && used + SEP + span(h) <= width) { cur.push(h); used += SEP + span(h) }
    else { lines.push([h]); used = span(h) }
  }
  if (lines.length <= max) return lines
  const kept = lines.slice(0, max), last = kept[max - 1]!
  let left = lines.slice(max).reduce((s, l) => s + l.length, 0)
  const fits = () => last.reduce((s, h) => s + span(h) + SEP, 0) + span({ key: `+${left}`, label: "more" }) <= width
  while (last.length && !fits()) { last.pop(); left++ }
  last.push({ key: `+${left}`, label: "more" })
  return kept
}
