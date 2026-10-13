export type Affinities = { admires: string[]; needles: string[]; covers: string[] }
export type Relation = "friend" | "rival" | "none"
type SoulLike = { sections: Record<string, string> }

const fold = (s: string) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase()
const VERBS: [keyof Affinities, RegExp][] = [["covers", /would cover for/g], ["admires", /\badmires\b/g], ["needles", /\bneedles\b/g]]

/** the People section → who they admire / needle / would cover for, by verb; names off the bench are ignored */
export function affinities(people: string, bench: string[]): Affinities {
  const text = fold(people), out: Affinities = { admires: [], needles: [], covers: [] }
  const marks = VERBS.flatMap(([k, re]) => [...text.matchAll(re)].map((m) => ({ k, at: m.index!, end: m.index! + m[0].length })))
    .sort((a, b) => a.at - b.at)
  marks.forEach((m, i) => {
    // a clause runs to the next verb or the next period, whichever is first
    const clause = text.slice(m.end, marks[i + 1]?.at ?? text.length).split(".")[0]!
    for (const n of bench) if (new RegExp(`\\b${fold(n)}\\b`).test(clause) && !out[m.k].includes(fold(n))) out[m.k].push(fold(n))
  })
  return out
}

/** symmetric: either liking the other makes friends (admires beats needles); else either needling makes rivals */
export function relation(a: string, b: string, souls: Record<string, SoulLike | undefined>, bench: string[]): Relation {
  const ab = affinities(souls[a]?.sections.People ?? "", bench), ba = affinities(souls[b]?.sections.People ?? "", bench)
  const likes = (x: Affinities, who: string) => x.admires.includes(who) || x.covers.includes(who)
  if (likes(ab, b) || likes(ba, a)) return "friend"
  if (ab.needles.includes(b) || ba.needles.includes(a)) return "rival"
  return "none"
}
