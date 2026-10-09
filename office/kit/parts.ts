// The parts library: things a figure wears, in slots, each drawn once per view as row overlays on
// figure()'s 12-wide rows (sprites.ts). A part has dials (crown height, brim width, hue…); a Look
// names a part and its dial values, so the library is data and `figure()` has no branch per part.
// In an overlay `.` leaves the pixel alone and `_` clears it (the hair a hat hides).

/** row index → that row's 12 chars; a row left out (or undefined) is untouched */
export type View = { [row: number]: string | undefined }
export type Gear = { front?: View; side?: View; back?: View }
export const SLOTS = ["head", "eyes", "mouth", "neck", "back", "hand"] as const
export type Slot = (typeof SLOTS)[number]
export type DialVals = Record<string, string | number>
/** what a Look stores: the part's id and any dial it sets; an unset or unknown dial is its first option */
export type PartSpec = { id: string; dials?: DialVals }
export type Part = { slot: Slot; dials: Record<string, readonly (string | number)[]>; draw: (d: DialVals) => Required<Gear> }

const part = <D extends DialVals>(slot: Slot, dials: { [K in keyof D]: readonly D[K][] }, draw: (d: D) => Required<Gear>): Part =>
  ({ slot, dials, draw: draw as (d: DialVals) => Required<Gear> })

const W = 12
/** `s` at column `col` of a 12-wide row */
const at = (col: number, s: string) => ".".repeat(col) + s + ".".repeat(W - col - s.length)
/** `s` centred; `shift` nudges it toward the back of the head (the side view) */
const mid = (s: string, shift = 0) => at(Math.min(W - s.length, ((W - s.length) >> 1) + shift), s)
const none: View = {}

// colours outside the body must read 3:1 on the room (test/wcag.test.ts): never `k`, `f`, `s`, `p`, `b`
const HUES = ["r", "g", "y", "w", "c"] as const

/** a hat: crown rows end just above the brim row; the hair above the brim and beside the crown is cleared */
function hat(brimAt: number, crown: string[], brim: string): Required<Gear> {
  const draw = (shift: number): View => {
    const o: View = {}
    for (let r = 0; r < brimAt; r++) {
      const k = r - (brimAt - crown.length)
      o[r] = k < 0 ? "_".repeat(W) : mid(crown[k]!, shift).replaceAll(".", "_")
    }
    o[brimAt] = mid(brim, shift)
    return o
  }
  return { front: draw(0), back: draw(0), side: draw(1) }
}
const rep = (c: string, n: number) => c.repeat(n)
const rows = (from: number, to: number, f: (r: number) => string): View => Object.fromEntries(Array.from({ length: to - from + 1 }, (_, i) => [from + i, f(from + i)]))

export const PARTS: Record<string, Part> = {
  // head: the brim sits on hair row 3, a crown of up to 3 rows above it
  tophat: part("head", { hue: HUES, crown: [2, 3], brim: [10, 12], band: ["none", "r", "w"] }, (d) =>
    hat(3, Array.from({ length: d.crown }, (_, i) => rep(i === d.crown - 1 && d.band !== "none" ? d.band : d.hue, 6)), rep(d.hue, d.brim))),
  beanie: part("head", { hue: HUES, cuff: ["same", "w", "r"], pom: [0, 1] }, (d) =>
    hat(3, [...(d.pom ? [rep(d.hue, 2)] : []), rep(d.hue, 6), rep(d.hue, 8)], rep(d.cuff === "same" ? d.hue : d.cuff, 8))),
  cowboy: part("head", { hue: HUES, band: ["none", "r", "w"] }, (d) =>
    hat(3, [`${rep(d.hue, 2)}..${rep(d.hue, 2)}`, rep(d.band === "none" ? d.hue : d.band, 8)], rep(d.hue, 12))),
  wizard: part("head", { hue: HUES, star: [0, 1], brim: [10, 12] }, (d) =>
    hat(3, [rep(d.hue, 2), rep(d.hue, 4), d.star ? `${rep(d.hue, 2)}y${rep(d.hue, 3)}` : rep(d.hue, 6)], rep(d.hue, d.brim))),
  crown: part("head", { jewel: ["r", "g", "w"], tall: [0, 1] }, (d) =>
    hat(3, [...(d.tall ? ["y.y..y.y"] : []), "y.yyyy.y"], `yyy${d.jewel}${d.jewel}yyy`)),
  propeller: part("head", { hue: HUES, blade: ["r", "g", "y", "w"] }, (d) =>
    hat(3, [`${rep(d.blade, 3)}..${rep(d.blade, 3)}`, rep(d.hue, 2), rep(d.hue, 6)], rep(d.hue, 8))),
  bunny: part("head", { hue: HUES, ears: [2, 3], band: ["r", "w", "g"] }, (d) =>
    hat(3, Array.from({ length: d.ears }, () => `${d.hue}....${d.hue}`), rep(d.band, 8))),

  // eyes: row 6 holds the eyes (front cols 3 and 8, side col 2)
  glasses: part("eyes", { frame: ["round", "shades"], tint: ["k", "g", "r"] }, (d) =>
    d.frame === "round"
      ? { front: { 6: `..${d.tint}${d.tint}..${d.tint}${d.tint}....` }, side: { 6: `.${d.tint}${d.tint}.........` }, back: none }
      : { front: { 6: at(2, rep(d.tint, 8)) }, side: { 6: at(1, rep(d.tint, 4)) }, back: none }),
  monocle: part("eyes", { eye: ["l", "r"], ring: ["y", "g", "r"] }, (d) => {
    const e = d.eye === "l" ? 3 : 8
    return {
      front: { 6: at(e - 1, `${d.ring}.${d.ring}`), 7: at(e - 1, rep(d.ring, 3)), 8: at(e === 3 ? 2 : 9, d.ring) },
      side: { 6: at(1, `${d.ring}.${d.ring}`), 7: at(1, rep(d.ring, 3)), 8: at(1, d.ring) },
      back: none,
    }
  }),
  eyepatch: part("eyes", { eye: ["l", "r"] }, (d) => {
    const e = d.eye === "l" ? 3 : 8
    return { front: { 5: at(e, "k"), 6: at(e - 1, "kkk"), 7: at(e - 1, "kkk") }, side: { 6: at(2, "kk"), 7: at(2, "kk") }, back: none }
  }),

  // mouth: facial hair in the hair colour (`h`); the face's mouth is row 8, the lip row 7
  moustache: part("mouth", { style: ["pencil", "walrus", "handlebar"] }, (d) =>
    d.style === "pencil" ? { front: { 7: mid("hhhh") }, side: { 7: at(2, "hh") }, back: none }
      : d.style === "walrus" ? { front: { 7: mid("hhhhhh"), 8: at(3, "h....h") }, side: { 7: at(2, "hhh"), 8: at(2, "h") }, back: none }
      : { front: { 7: at(2, "h.hhhh.h") }, side: { 7: at(2, "hhh"), 8: at(3, "h") }, back: none }),
  beard: part("mouth", { style: ["goatee", "full"] }, (d) =>
    d.style === "goatee" ? { front: { 8: at(4, "hhhh"), 9: mid("hh") }, side: { 8: at(2, "hh"), 9: at(3, "h") }, back: none }
      : { front: { 7: at(2, "h......h"), 8: at(2, "hhhhhhhh"), 9: at(3, "hhhhhh") }, side: { 7: at(2, "hhhhhh"), 8: at(2, "hhhhh"), 9: at(4, "hh") }, back: none }),

  // neck: the neck is row 9, the shoulders row 10
  scarf: part("neck", { hue: HUES, tail: ["short", "long"] }, (d) => ({
    front: { 9: mid(rep(d.hue, 6)), 10: mid(rep(d.hue, 4)), ...rows(11, d.tail === "long" ? 12 : 11, () => at(4, rep(d.hue, 2))) },
    side: { 9: at(4, rep(d.hue, 4)), 10: at(3, rep(d.hue, 4)), ...rows(11, d.tail === "long" ? 12 : 11, () => at(2, rep(d.hue, 2))) },
    back: { 9: mid(rep(d.hue, 6)), 10: mid(rep(d.hue, 4)) },
  })),
  bowtie: part("neck", { hue: ["r", "g", "y"], size: [1, 2] }, (d) => ({
    front: d.size === 1 ? { 10: mid(rep(d.hue, 4)) } : { 10: mid(rep(d.hue, 6)), 11: at(4, `${d.hue}..${d.hue}`) },
    side: { 10: at(3, rep(d.hue, d.size + 1)) },
    back: none,
  })),
  medal: part("neck", { ribbon: ["r", "g", "w"], metal: ["y", "w"] }, (d) => ({
    front: { 11: at(8, d.ribbon), 12: at(8, rep(d.metal, 2)) },
    side: { 11: at(3, d.ribbon), 12: at(3, d.metal) },
    back: none,
  })),

  // back: behind the body from the front and the side, over it from behind
  cape: part("back", { hue: HUES, length: ["short", "long"], trim: ["same", "w", "y"], emblem: [0, 1] }, (d) => {
    const end = d.length === "long" ? 17 : 14, trim = d.trim === "same" ? d.hue : d.trim, edge = (r: number) => (r === end ? trim : d.hue)
    return {
      front: rows(10, end, (r) => `${edge(r)}${".".repeat(10)}${edge(r)}`),
      side: rows(10, end, (r) => at(9, rep(edge(r), 2))),
      back: { ...rows(10, end, (r) => at(1, rep(edge(r), 10))), ...(d.emblem ? { 12: at(5, "yy") } : {}) },
    }
  }),
  backpack: part("back", { hue: HUES, size: [1, 2] }, (d) => ({
    front: rows(11, 11 + d.size, () => `${d.hue}${".".repeat(10)}${d.hue}`),
    side: rows(10, 12 + d.size, () => at(9, rep(d.hue, 2))),
    back: rows(10, 12 + d.size, () => (d.size === 2 ? at(2, rep(d.hue, 8)) : at(3, rep(d.hue, 6)))),
  })),
  wings: part("back", { hue: HUES, span: ["small", "big"] }, (d) => {
    const [from, to] = d.span === "big" ? [7, 12] : [9, 11], pair = () => `${rep(d.hue, 2)}${".".repeat(8)}${rep(d.hue, 2)}`
    return { front: rows(from, to, pair), side: rows(from, to, () => at(9, rep(d.hue, 3))), back: rows(from, to, pair) }
  }),

  // hand: held at the hand beside the torso (front and back share it)
  mug: part("hand", { hue: HUES, steam: [0, 1] }, (d) => {
    const v: View = { ...rows(11, 12, () => at(10, rep(d.hue, 2))), ...(d.steam ? { 10: at(10, "w") } : {}) }
    return { front: v, side: { ...rows(11, 12, () => at(1, rep(d.hue, 2))), ...(d.steam ? { 10: at(1, "w") } : {}) }, back: v }
  }),
  wand: part("hand", { tip: ["y", "r", "g", "w"], len: [2, 3] }, (d) => {
    const v = (col: number): View => ({ [13 - d.len]: at(col, d.tip), ...rows(14 - d.len, 14, () => at(col, "c")) })
    return { front: v(11), side: v(1), back: v(11) }
  }),
  balloon: part("hand", { hue: HUES, string: [3, 4] }, (d) => {
    const top = 10 - d.string, v = (col: number): View => ({ ...rows(top, top + 2, () => at(col - 1, rep(d.hue, 2))), ...rows(top + 3, 12, () => at(col, "w")) })
    return { front: v(10), side: v(1), back: v(10) }
  }),
}
export const PART_IDS = Object.keys(PARTS)
export const idsIn = (slot: Slot) => PART_IDS.filter((id) => PARTS[id]!.slot === slot)

/** a spec's dials with the defaults filled in; a value the part doesn't offer falls back to its first option */
export function dialsOf(p: Part, set: DialVals | undefined): DialVals {
  return Object.fromEntries(Object.entries(p.dials).map(([k, opts]) => [k, opts.includes(set?.[k] as never) ? set![k]! : opts[0]!]))
}
const drawn = new Map<string, Required<Gear>>()
/** a spec's pixels, or undefined for a part the library no longer has (a stale looks.json) */
export function gearOf(spec: PartSpec): Required<Gear> | undefined {
  const p = PARTS[spec.id]
  if (!p) return undefined
  const d = dialsOf(p, spec.dials), key = spec.id + JSON.stringify(d)
  let g = drawn.get(key)
  if (!g) drawn.set(key, (g = p.draw(d)))
  return g
}
/** the next part in a slot after `cur`, then none, then the first again: what the look card cycles */
export function nextPart(slot: Slot, cur: PartSpec | undefined): PartSpec | undefined {
  const ids = idsIn(slot), i = cur ? ids.indexOf(cur.id) : -1
  return i + 1 < ids.length ? { id: ids[i + 1]! } : undefined
}
