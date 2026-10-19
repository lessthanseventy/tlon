// The finder's matcher: the query's letters in order somewhere in the text, scored so a match at
// word starts and in runs beats one scattered through it. Case-insensitive.

const atWordStart = (t: string, at: number) => at === 0 || /[\s/#·:_\-.]/.test(t[at - 1]!)

/**
 * the fewest separate runs of `q` (contiguous stretches of `t`) that spell it in order, counting only
 * runs that start at a word start, except the first, which may start anywhere; Infinity when it can't be spelled that way
 */
function runs(q: string, t: string): number {
  const memo = new Map<number, number>()
  const go = (qi: number, ti: number, joined: boolean): number => {
    if (qi === q.length) return 0
    const key = (qi * (t.length + 1) + ti) * 2 + (joined ? 1 : 0)
    const hit = memo.get(key)
    if (hit !== undefined) return hit
    let best = Infinity
    for (let at = ti; at < t.length; at++) {
      if (t[at] !== q[qi]) continue
      const extends_ = joined && at === ti
      if (!extends_ && qi > 0 && !atWordStart(t, at)) continue
      best = Math.min(best, (extends_ ? 0 : 1) + go(qi + 1, at + 1, true))
    }
    memo.set(key, best)
    return best
  }
  return go(0, 0, false)
}

/**
 * a score for `text` against `query` (higher is better), or null when the letters aren't all there in order
 * or are scattered: a word of the query may be spelled in at most one more run than there are words
 */
export function score(query: string, text: string): number | null {
  const q = query.toLowerCase().replace(/\s+/g, ""), t = text.toLowerCase()
  if (!q) return 0
  if (runs(q, t) > query.trim().split(/\s+/).length + 1) return null
  const whole = t.indexOf(q)
  let s = whole < 0 ? 0 : atWordStart(t, whole) ? 14 : 10, ti = 0, last = -2
  for (const c of q) {
    const at = t.indexOf(c, ti)
    if (at < 0) return null
    const start = atWordStart(t, at)
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
