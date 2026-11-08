// The office's own trophies: tallies of what happened in the room (kept by the TUI in its state dir),
// and the table of what each earns. Pure; the TUI feeds it and writes it.

export type Tally = { drills: number; treats: number; balloons: number; planes: number; greenRun: number; greenDay: string; secrets: string[] }
export const NONE: Tally = { drills: 0, treats: 0, balloons: 0, planes: 0, greenRun: 0, greenDay: "", secrets: [] }

export type Counter = "drills" | "treats" | "balloons" | "planes" | "greenRun"
export type Trophy = { id: string; name: string; counter: Counter; goal: number }
export const TROPHIES: Trophy[] = [
  { id: "drill", name: "first fire drill", counter: "drills", goal: 1 },
  { id: "treats", name: "100 treats", counter: "treats", goal: 100 },
  { id: "balloons", name: "1,000 balloons read", counter: "balloons", goal: 1000 },
  { id: "planes", name: "10 planes caught", counter: "planes", goal: 10 },
  { id: "green", name: "a week of green nights", counter: "greenRun", goal: 7 },
]

/** the easter eggs a person can find, by id: the sandbox shows how many of them are found */
export const SECRETS = ["konami", "babel", "clock"]

export const earned = (t: Tally, tr: Trophy): boolean => t[tr.counter] >= tr.goal
export const won = (t: Tally): Trophy[] => TROPHIES.filter((tr) => earned(t, tr))

export function bump(t: Tally, counter: Exclude<Counter, "greenRun">, n = 1): Tally {
  return { ...t, [counter]: t[counter] + n }
}

export function findSecret(t: Tally, id: string): Tally {
  return SECRETS.includes(id) && !t.secrets.includes(id) ? { ...t, secrets: [...t.secrets, id] } : t
}

const dayBefore = (day: string): string => {
  const d = new Date(`${day}T12:00:00`)
  d.setDate(d.getDate() - 1)
  return localDay(d)
}
export const localDay = (d: Date): string =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`

/** a night is green when the evening (from 20:00) passes with no red build; a red one ends the run */
export function night(t: Tally, now: Date, red: boolean): Tally {
  if (red) return t.greenRun ? { ...t, greenRun: 0 } : t
  if (now.getHours() < 20) return t
  const day = localDay(now)
  if (t.greenDay === day) return t
  return { ...t, greenRun: t.greenDay === dayBefore(day) ? t.greenRun + 1 : 1, greenDay: day }
}

/** the trophies `after` has that `before` did not */
export const newlyWon = (before: Tally, after: Tally): Trophy[] => won(after).filter((tr) => !earned(before, tr))

const count = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) && v >= 0 ? Math.floor(v) : 0)
export function parse(raw: string): Tally {
  try {
    const j = JSON.parse(raw) as Record<string, unknown>
    return {
      drills: count(j.drills), treats: count(j.treats), balloons: count(j.balloons), planes: count(j.planes), greenRun: count(j.greenRun),
      greenDay: typeof j.greenDay === "string" ? j.greenDay : "",
      secrets: Array.isArray(j.secrets) ? j.secrets.filter((s): s is string => SECRETS.includes(s as string)) : [],
    }
  } catch { return NONE }
}
export const serialize = (t: Tally): string => `${JSON.stringify(t)}\n`

/** each trophy as a card row: a star when won, else how far along; then the secrets found */
export function rows(t: Tally): { won: boolean; name: string; note: string }[] {
  return [
    ...TROPHIES.map((tr) => ({ won: earned(t, tr), name: tr.name, note: earned(t, tr) ? "won" : `${t[tr.counter]}/${tr.goal}` })),
    { won: t.secrets.length === SECRETS.length, name: "secrets", note: `${t.secrets.length}/${SECRETS.length}` },
  ]
}
