// The finder's matcher: the query's letters in order somewhere in the text, scored so a match at
// word starts and in runs beats one scattered through it. Case-insensitive.

/** a score for `text` against `query` (higher is better), or null when the letters aren't all there in order */
export function score(query: string, text: string): number | null {
  const q = query.toLowerCase().replace(/\s+/g, ""), t = text.toLowerCase()
  if (!q) return 0
  let s = 0, ti = 0, last = -2
  for (const c of q) {
    const at = t.indexOf(c, ti)
    if (at < 0) return null
    const start = at === 0 || /[\s/#·:_\-.]/.test(t[at - 1]!)
    s += 1 + (start ? 8 : 0) + (at === last + 1 ? 5 : 0) - (last < 0 ? 0 : Math.min(3, (at - ti) * 0.1))
    last = at; ti = at + 1
  }
  return s
}

/** `items` that match, best first; `textOf` is what each is matched on */
export function rank<T>(query: string, items: T[], textOf: (x: T) => string): T[] {
  return items
    .map((x, i) => ({ x, i, s: score(query, textOf(x)) }))
    .filter((r) => r.s !== null)
    .sort((a, b) => b.s! - a.s! || a.i - b.i)
    .map((r) => r.x)
}
