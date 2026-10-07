// The office's easter eggs that are pure functions: what the clock shows, the Konami code, a page of
// the Library of Babel, a cat's keyboard, the night owl's hours. The room and the TUI do the rest.

/** the wall clock's face: 404 at four minutes past four (the time cannot be found), π at 3:14 */
export function clockFace(now: Date): string {
  const h = now.getHours() % 12, m = now.getMinutes()
  if (h === 4 && m === 4) return "404"
  if (h === 3 && m === 14) return "π"
  return `${String(now.getHours()).padStart(2, "0")}:${String(m).padStart(2, "0")}`
}

export const KONAMI = ["up", "up", "down", "down", "left", "right", "left", "right", "b", "a"]

/** the last keys pressed end with the Konami code */
export const isKonami = (keys: readonly string[]) =>
  keys.length >= KONAMI.length && KONAMI.every((k, i) => keys[keys.length - KONAMI.length + i] === k)

/** the Library's alphabet: letters, the space, the comma and the full stop */
export const BABEL_ALPHABET = "abcdefghijklmnopqrstuvwxyz ,."

// what a librarian might find, once in a thousand pages, among the noise
const FOUND = [
  "somewhere in these rooms is the book of you",
  "the librarian who read this page went home happy",
  "every page is true in some other library",
  "you were looking for this one",
  "a hexagon further on, a man is reading this too",
  "the catalogue of catalogues is on the next shelf",
]

/** a page of the Library of Babel, `lines` of `width`; once in a thousand pages, one line means something */
export function babelPage(lines: number, width: number, rng: () => number = Math.random): string[] {
  const line = () => Array.from({ length: width }, () => BABEL_ALPHABET[Math.floor(rng() * BABEL_ALPHABET.length)]!).join("")
  const page = Array.from({ length: lines }, line)
  if (rng() < 0.001) {
    const found = FOUND[Math.floor(rng() * FOUND.length)]!.slice(0, width)
    page[Math.floor(rng() * lines)] = found.padEnd(width, " ")
  }
  return page
}

const ROWS = ["qwertyuiop[]", "asdfghjkl;'", "zxcvbnm,./"]

/** what a cat standing on a keyboard types: a run along one row, some keys held down */
export function keyMash(rng: () => number = Math.random): string {
  const row = ROWS[Math.floor(rng() * ROWS.length)]!
  let out = ""
  for (let i = 0, n = 10 + Math.floor(rng() * 8); i < n; i++) {
    const ch = row[Math.floor(rng() * row.length)]!
    out += rng() < 0.25 ? ch.repeat(2 + Math.floor(rng() * 3)) : ch
  }
  return out
}

/** the small hours: the office dims, people yawn, and Nina gets ideas */
export const nightOwl = (hour: number) => hour >= 0 && hour < 5
