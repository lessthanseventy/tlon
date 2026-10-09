// The office's people and things as sprites: one char per pixel, "." clear; letters are looked up
// in a paint map at draw time, so every colour is a ROLE. Looks and habits come from a hash of the
// agent's name, gear from its archetype — the same person looks the same in every room.
import { ROLE, type Role } from "./palette"
import { gearOf, idsIn, PARTS, SLOTS, type PartSpec, type Slot, type View } from "./parts"

export type Dir = "down" | "up" | "left" | "right"
export type Pose = "stand" | "sit" | "couch"
/** where someone likes to idle */
export type Fav = "board" | "couch" | "cooler" | "coffee"
export type Hair = "mop" | "spiky" | "bun" | "long" | "bald" | "curly" | "mohawk" | "parted"
export type Body = "average" | "tall" | "short" | "round"
export type Outfit = "hoodie" | "labcoat" | "apron" | "suit" | "poncho"
export type Accessory = "glasses" | "headphones"
export type Look = {
  hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number
  skinRole?: Role; outfit?: Outfit; accessory?: Accessory
  body?: Body; parts?: Partial<Record<Slot, PartSpec>>
  custom?: Partial<Record<"front" | "side" | "back", string[]>>
}
export const SKIN_ROLES: Role[] = ["builder", "surveyor", "reviewer", "assistant", "planner", "body"]

export function hash(s: string) { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0 }

/** the styles lookOf rolls from: fixed, because a name hashes to an index into it */
export const HAIRS: Hair[] = ["mop", "spiky", "bun", "long", "bald"]
/** every style, for the look card and rollLook; lookOf never picks past HAIRS */
export const HAIR_STYLES: Hair[] = [...HAIRS, "curly", "mohawk", "parted"]
export const HAIR_ROLES: Role[] = ["inactive", "structure", "meta", "borderInactive"]
const TOP: Record<Hair, string[]> = {
  mop: ["............", "............", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  spiky: ["............", "...h..h..h..", "..hhhhhhhh..", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  bun: [".....hh.....", "....hhhh....", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  long: ["............", "............", "...hhhhhh...", "..hhhhhhhh..", ".hhhhhhhhhh.", ".hhffffffhh."],
  bald: ["............", "............", "............", "...ffffff...", "..ffffffff..", "..ffffffff.."],
  curly: ["............", "...hhhhhh...", "..hhhhhhhh..", ".hhhhhhhhhh.", ".hhhhhhhhhh.", "..hffffffh.."],
  mohawk: ["............", ".....hh.....", "....hhhh....", "...fhhhhf...", "..ffhhhhff..", "..ffffffff.."],
  parted: ["............", "...hhhhh....", "..hhhhhhhh..", "..hhhfhhhh..", "..hhhhhhhh..", "..hffffffh.."],
}
/** hairless from the side (the hair's own rows turn to skin) before its overlay */
const SIDE_BARE = new Set<Hair>(["bald", "mohawk"])
/** a style's side-view rows over SIDE_HEAD */
const SIDE_OVER: Partial<Record<Hair, View>> = {
  bun: { 0: ".......hh...", 1: "......hhhh.." },
  spiky: { 1: "....h.h.h..." },
  curly: { 1: "....hhhhh...", 2: "...hhhhhhhh.", 3: "..hhhhhhhhhh" },
  mohawk: { 1: "....hhh.....", 2: "....hhhh....", 3: "....hhhh...." },
}
const FACE = ["..fkffffkf..", "..ffffffff..", "...ffkkff...", ".....ff....."]
const SHUT = "..fkkffkkf.."
const SIDE_HEAD = ["............", "............", "....hhhhh...", "...hhhhhhhh.", "..hhhhhhhhh.", "..fffffhhhh.", ".fkffffhhh..", "..fffffffh..", "..kfffff....", ".....ff....."]
const TORSO = ["..ssssssss..", ".ssssssssss.", ".ssssssssss.", ".fssssssssf.", "..ssssssss.."]
const SIDE_TORSO = ["...ssssss...", "...ssssss...", "...sfssss...", "...ssssss...", "...ssssss..."]
const LEGS: Record<string, string[]> = {
  stand: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..bb....bb.."],
  a: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..bb....pp..", "........bb.."],
  b: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....bb..", "..bb........"],
  couch: ["..pppppppp..", "..pppppppp..", "..pp....pp..", "..bb....bb..", "............"],
  sideStand: ["...pppppp...", "....pppp....", "....pp.p....", "....pp.p....", "...bbb.bb..."],
  sideA: ["...pppppp...", "...pp..pp...", "..pp....pp..", ".pp......pp.", ".bb......bb."],
  sideB: ["...pppppp...", "....pppp....", "....pppp....", "....pp.p....", "...bbbbb...."],
}
/** body shapes: all 12 wide, with the torso rows (10-14) in place so every overlay below stays valid;
 * a shape differs in its torso's width and in how many leg rows it stands on (tall 7, short 3), so
 * its walk and sit frames are drawn here once */
export const BODIES: Body[] = ["average", "tall", "short", "round"]
const BODY: Record<Body, { torso: string[]; sideTorso: string[]; legs: Record<string, string[]> }> = {
  average: { torso: TORSO, sideTorso: SIDE_TORSO, legs: LEGS },
  round: {
    torso: [".ssssssssss.", "ssssssssssss", "ssssssssssss", "fssssssssssf", ".ssssssssss."],
    sideTorso: ["..ssssssss..", "..ssssssss..", "..sfssssss..", "..ssssssss..", "..ssssssss.."],
    legs: LEGS,
  },
  tall: {
    torso: TORSO, sideTorso: SIDE_TORSO,
    legs: {
      stand: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..bb....bb.."],
      a: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..bb....pp..", "........bb.."],
      b: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..pp....bb..", "..bb........"],
      couch: ["..pppppppp..", "..pppppppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..bb....bb..", "............"],
      sideStand: ["...pppppp...", "....pppp....", "....pp.p....", "....pp.p....", "....pp.p....", "....pp.p....", "...bbb.bb..."],
      sideA: ["...pppppp...", "...pp..pp...", "..pp....pp..", "..pp....pp..", ".pp......pp.", ".pp......pp.", ".bb......bb."],
      sideB: ["...pppppp...", "....pppp....", "....pppp....", "....pppp....", "....pp.p....", "....pp.p....", "...bbbbb...."],
    },
  },
  short: {
    torso: TORSO, sideTorso: SIDE_TORSO,
    legs: {
      stand: ["..pppppppp..", "..pp....pp..", "..bb....bb.."],
      a: ["..pppppppp..", "..bb....pp..", "........bb.."],
      b: ["..pppppppp..", "..pp....bb..", "..bb........"],
      couch: ["..pppppppp..", "..pppppppp..", "..bb....bb.."],
      sideStand: ["...pppppp...", "....pp.p....", "...bbb.bb..."],
      sideA: ["...pppppp...", "..pp....pp..", ".bb......bb."],
      sideB: ["...pppppp...", "....pppp....", "...bbbbb...."],
    },
  },
}
/** custom views are drawn 20 tall, so a custom look keeps the average build for its generated views */
const bodyOf = (look: Look): Body => (look.custom ? "average" : look.body ?? "average")
/** rows a standing figure of this look is tall: where its head sits above its feet */
export const heightOf = (look: Look) => 15 + BODY[bodyOf(look)].legs.stand!.length

// archetype gear, as row overlays per view
type Gear = { front?: View; side?: View; back?: View }
const HARDHAT = { 1: "....yyyy....", 2: "..yyyyyyyy..", 3: ".yyyyyyyyyy." }
const SAFARI = { 1: "...cccccc...", 2: "...cccccc...", 3: "cccccccccccc" }
const GEAR: Record<string, Gear> = {
  builder: { front: HARDHAT, back: HARDHAT, side: { 1: "....yyyy....", 2: "...yyyyyy...", 3: "yyyyyyyyyy.." } },
  surveyor: { front: SAFARI, back: SAFARI, side: SAFARI },
  reviewer: { front: { 6: "..gkggggkg.." }, side: { 6: ".gkgg......." } },
  assistant: {
    front: { 2: "...eeeeee...", 5: ".e........e.", 6: ".e........e.", 7: ".e........e.", 8: ".eee........" },
    back: { 2: "...eeeeee...", 5: ".e........e.", 6: ".e........e." },
    side: { 2: "....eeeee...", 5: ".......e....", 6: ".......e....", 7: "..eeeeee...." },
  },
  researcher: { front: { 10: "........ggg.", 11: ".......g...g", 12: "........ggg.", 13: ".......c...." }, side: { 10: ".ggg........", 11: "g...g.......", 12: ".ggg........", 13: "....c......." } },
  librarian: { front: { 11: "...wwwkwww..", 12: "...wwwkwww..", 13: "...ccccccc.." }, side: { 11: ".wwkww......", 12: ".ccccc......" } },
  planner: { front: { 11: ".......cc...", 12: "......wwww..", 13: "......wwww..", 14: "......wwww.." }, side: { 11: "..cc........", 12: ".wwww.......", 13: ".wwww......." } },
}
export const OUTFIT: Record<Outfit, Gear> = {
  apron: { front: { 11: "...wwwwww...", 12: "...wwwwww...", 13: "...wwwwww...", 14: "...wwwwww..." }, back: { 11: ".....ww.....", 12: ".....ww....." }, side: { 11: "...wwww.....", 12: "...wwww.....", 13: "...wwww.....", 14: "...wwww....." } },
  suit: { front: { 10: "..kk....kk..", 11: "..kk.ww.kk..", 12: "..kkk..kkk..", 13: "..kkk..kkk.." }, back: { 10: ".kkkkkkkkkk.", 11: ".kkkkkkkkkk.", 12: ".kkkkkkkkkk." }, side: { 10: "...kkkkkk...", 11: "...kkkkkk...", 12: "...kkkkkk..." } },
  poncho: { front: { 10: ".rrrrrrrrrr.", 11: "rrrrrrrrrrrr", 12: "rr.rrrrrr.rr" }, back: { 10: ".rrrrrrrrrr.", 11: "rrrrrrrrrrrr", 12: "rr.rrrrrr.rr" }, side: { 10: "..rrrrrrrr..", 11: "..rrrrrrrr..", 12: "..rrrrrrrr.." } },
  hoodie: { front: { 10: ".oooooooooo.", 11: ".oo........o" }, back: { 10: ".oooooooooo." }, side: { 10: "..oooooooo.." } },
  labcoat: { front: { 9: ".wwwwwwwwww.", 10: "ww........ww", 11: "ww........ww" }, back: { 9: ".wwwwwwwwww." }, side: { 9: "wwwwwwwwwwww" } },
}
export const ACCESSORY: Record<Accessory, Gear> = {
  glasses: { front: { 6: "..kk..kk...." }, side: { 6: ".kk........." } },
  headphones: { front: { 5: ".k........k." }, back: { 5: ".k........k." }, side: { 5: "k..........." } },
}
const BADGE = { 11: "...y........", 12: "..yyy......." }
const TIE = { 10: ".....rr.....", 11: ".....rr.....", 12: "....rrrr....", 13: ".....rr....." }

export const DECOR = [
  [".l.l.", "lllll", ".lll.", "..l..", ".ooo.", ".ooo."], // plant
  ["mmmm.", "mmm.m", "mmmm.", "mmm.."], // mug (steam drawn over it)
  ["..yy.", "..yya", "yyyy.", ".yyy."], // rubber duck
  ["akl", "akl", "akl", "akl"], // books
  ["..l..", "l.l.l", "lllll", "..l..", ".ooo.", ".ooo."], // cactus
  ["oooo", "okko", "oaao", "oooo"], // photo
]
export const COOLER = [".kkkkkk.", ".kkkkkk.", ".kkkkkk.", "..kkkk..", "mmmmmmmm", "mmmmmmmm", "mmaammmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "mmmmmmmm", "o......o", "oo....oo"]
export const COFFEE = ["mmmmmmm", "mlmmmmm", "mmmmmmm", "m.....m", "m..c..m", "m.ccc.m", "mmmmmmm"]
export const BIG_PLANT = ["...l..l...", ".l.ll.l.l.", "llllllllll", ".llllllll.", "..llllll..", "...llll...", "....ll....", "....ll....", "..oooooo..", "..oooooo..", "...oooo..."]
export const BUBBLE = [".aaaaa.", "aaaaaaa", "aaaaaaa", "aaaaaaa", "aaaaaaa", "aaaaaaa", ".aaaaa.", "..a...."]
export const GLYPH: Record<string, string[]> = {
  "!": ["..k..", "..k..", "..k..", ".....", "..k.."],
  "?": [".kkk.", "....k", "..kk.", ".....", "..k.."],
  "…": [".....", ".....", ".....", ".....", "k.k.k"],
  "✎": ["....k", "...k.", "..k..", ".k...", "kk..."],
  "♪": ["..kk.", "..k.k", "..k..", "kkk..", "kk..."],
  "~": [".....", ".k...", "k.k.k", "...k.", "....."],
  "*": ["k.k.k", ".kkk.", "kkkkk", ".kkk.", "k.k.k"],
  "♥": [".k.k.", "kkkkk", "kkkkk", ".kkk.", "..k.."],
  "z": ["kkkkk", "...k.", "..k..", ".k...", "kkkkk"],
}
const SIGNATURES = ["♪", "♥", "*", "…"]
// a thought, not a word: the bubble trails off in a dot instead of pointing at the speaker
export const THOUGHT = [".aaaaa.", "aaaaaaa", "aaaaaaa", "aaaaaaa", "aaaaaaa", "aaaaaaa", ".aaaaa.", ".......", "..a...."]
/**
 * What someone mid-turn is doing (their seat's `doing`; `think` between tools), as a 5x5 glyph's
 * frames in their thought bubble, one per 400 ms frame — the shape says it, never the colour alone.
 */
export const ACTIVITY: Record<string, string[][]> = {
  // the dots fill in; now and then the bulb
  think: [[".....", ".....", ".....", ".....", "k...."], [".....", ".....", ".....", ".....", "k.k.."], [".....", ".....", ".....", ".....", "k.k.k"], [".....", ".....", ".....", ".....", "k.k.k"],
    [".....", ".....", ".....", ".....", "....."], [".kkk.", "k...k", ".k.k.", ".kkk.", ".kkk."]],
  // an open book, a page turning over
  read: [["kk.kk", "k.k.k", "k.k.k", "kkkkk", "....."], ["kk.kk", "k.k.k", "k.k.k", "kkkkk", "....."], ["..k..", "kkk.k", "k.k.k", "kkkkk", "....."], ["kk...", "k.kkk", "k.k.k", "kkkkk", "....."]],
  // a pencil, its line growing
  edit: [["....k", "...k.", "..k..", ".....", "k...."], [".....", "....k", "...k.", "..k..", "kk..."], [".....", ".....", "....k", "...k.", "kkk.."], [".....", ".....", ".....", "....k", "kkkk."]],
  // a prompt, its cursor blinking
  bash: [[".....", "k....", ".k...", "k.kkk", "....."], [".....", "k....", ".k...", "k....", "....."]],
  // a magnifier, sweeping
  search: [["kkk..", "k.k..", "kkk..", "...k.", "....k"], [".kkk.", ".k.k.", ".kkk.", "....k", "....."], ["..kkk", "..k.k", "..kkk", ".k...", "k...."], [".kkk.", ".k.k.", ".kkk.", "....k", "....."]],
  // a globe, turning
  web: [[".kkk.", "kk..k", "kkkkk", "kk..k", ".kkk."], [".kkk.", "k.k.k", "kkkkk", "k.k.k", ".kkk."], [".kkk.", "k..kk", "kkkkk", "k..kk", ".kkk."]],
  // a flask, bubbling
  test: [["..k..", ".k.k.", "k...k", "k.k.k", "kkkkk"], [".....", ".k.k.", "k.k.k", "k...k", "kkkkk"], ["...k.", ".k.k.", "k...k", "k...k", "kkkkk"]],
  // a letter, sealed and sent (a paper plane carries it off)
  delegate: [["kkkkk", "kk.kk", "k.k.k", "k...k", "kkkkk"]],
}
export const PLANE = ["kk..", ".kkk", "kk.."]
export const ARROW = ["vvvvv", ".vvv.", "..v.."]
// a note on the board: a squiggle in its author's colour, one of these by its id
export const SCRIBBLES = [["k.kk.k.kk", ".k..k.k..", "kk.k.kk.k"], ["kk.k.kk.k", "k.k..k.k.", ".kk.kk.kk"], [".k.kk.k.k", "kk.k..kk.", "k..kk.k.k"]]

// your cat, drawn facing right (mirrored for left): k fur, e her yellow eyes, c an eye shut, t the
// tail, w the tail wrapped round her, p pink (nose, tongue), g and j the gems of her collar (she is a
// princess; they sparkle)
const CAT_SIT = ["........k...k", "........kk.kk", "........kkkkk", "........kekek", "........kkpkk", "......kkgjgk.", ".....kkkkkkk.", "....kkkkkkkk.", "....kkkkkkkk.", "...kkkkk.k.k."]
const tail = (rows: string[], t: Record<number, string>) => rows.map((r, i) => (t[i] ? [...r].map((ch, j) => ((t[i]![j] ?? ".") !== "." ? t[i]![j]! : ch)).join("") : r))
export const CAT = {
  // the tail flicks; a frame with her eyes shut is the blink
  sit: [{ 6: "t....", 7: ".t...", 8: "..t..", 9: "..tt." }, { 6: "..t..", 7: "..t..", 8: "..t..", 9: "..tt." }, { 6: "....t", 7: "...t.", 8: "..t..", 9: "..tt." }].map((t) => tail(CAT_SIT, t)),
  blink: [tail(CAT_SIT, { 6: "t....", 7: ".t...", 8: "..t..", 9: "..tt." }).map((r) => r.replaceAll("e", "c"))],
  // a paw up at her mouth, then the tongue
  groom: [["........k...k", "........kk.kk", "........kkkkk", "........kckck", "........kkpkk", "......kkgjgkk", ".....kkkkkk.k", "....kkkkkk...", "....kkkkkkkk.", "...kkkkk...k."],
          ["........k...k", "........kk.kk", "........kkkkk", "........kckck", "........kkkpk", "......kkgjgpk", ".....kkkkkk.k", "....kkkkkk...", "....kkkkkkkk.", "...kkkkk...k."]],
  walk: [["..........k.k", "t.........kkk", ".t........kek", "..kkkkkkkgkkp", "..kkkkkkkjkk.", "..kkkkkkkkk..", "..k.k....k.k.", ".k...k..k...k"],
         ["..........k.k", ".t........kkk", "t.........kek", "..kkkkkkkgkkp", "..kkkkkkkjkk.", "..kkkkkkkkk..", "...kk....kk..", "...k.k...k.k."],
         ["..........k.k", "t.........kkk", ".t........kek", "..kkkkkkkgkkp", "..kkkkkkkjkk.", "..kkkkkkkkk..", "..k.k....k.k.", "..k..k....k.k"],
         ["..........k.k", ".t........kkk", "t.........kek", "..kkkkkkkgkkp", "..kkkkkkkjkk.", "..kkkkkkkkk..", "...kk....kk..", "..k..k...kk.."]],
  // curled up, breathing
  sleep: [[".............", "..k.k........", ".kkkk..kkkk..", "kckkkkkkkkkk.", "kkkkkkkkkkkkk", ".kwwwwwwwwwk."],
          ["..k.k........", ".kkkk.kkkkk..", "kkkkkkkkkkkk.", "kckkkkkkkkkkk", "kkkkkkkkkkkkk", ".kwwwwwwwwwk."]],
  // up from a nap: tail high, front paws out long, a yawn
  stretch: [["t............", ".t...........", "..kkkk...k.k.", "..kkkkkk.kkk.", "..k..kkkgkck.", "..k...kkjkpk.", "..k....kkkk..", "..k..kkkkkkkk"]],
  // batting the yarn: a paw out, then back
  play: [["........k...k", "........kk.kk", "........kkkkk", "........kekek", "........kkpkk", "......kkgjgkk", ".....kkkkkk.k", "....kkkkkkk..", "t...kkkkkkkk.", ".ttkkkkk.k.k."],
         ["........k...k", "........kk.kk", "........kkkkk", "........kekek", "........kkpkk", "......kkgjgk.", ".....kkkkkkkk", "....kkkkkkk.k", "t...kkkkkkkk.", ".ttkkkkk.k.k."]],
}
export const CAT_NAME = "Nina"

// the cat slot's other pets, drawn like Nina (facing right; k fur, e eye, c eye shut, t tail, p pink)
// with no collar, so no gems. `hop` lifts a frame a pixel: the top row is dropped, the feet leave the ground.
const hop = (rows: string[]) => [...rows.slice(1), ".".repeat(rows[0]!.length)]
const shut = (rows: string[]) => rows.map((r) => r.replaceAll("e", "c"))
const RABBIT_SIT = ["........k..k.", "........k..k.", "........kkkk.", "........kekk.", "........kkkkp", "......kkkkkk.", ".....kkkkkkk.", "....kkkkkkkk.", "...ttkkkkkkk.", "...tkkk.kk.k."]
const rabbitSit = [RABBIT_SIT, ["........kk.k.", ...RABBIT_SIT.slice(1)], ["........k.kk.", ...RABBIT_SIT.slice(1)]]
export const RABBIT = {
  sit: rabbitSit,
  blink: [shut(RABBIT_SIT)],
  groom: [shut(RABBIT_SIT), shut(rabbitSit[1]!)],
  walk: [RABBIT_SIT, hop(RABBIT_SIT), RABBIT_SIT, hop(RABBIT_SIT)],
  sleep: [[".............", ".....kk.kk...", "....kkkkkkk..", "...kkkckkkkp.", "..tkkkkkkkkk.", "..ttkkkkkkk.."], [".............", ".............", "....kkkkkkk..", "...kkkckkkkp.", "..tkkkkkkkkk.", "..ttkkkkkkk.."]],
  play: [hop(RABBIT_SIT), RABBIT_SIT],
  stretch: [hop(RABBIT_SIT)],
}

const BIRD_SIT = ["....kkk..", "...kkekp.", "...kkkk..", "..kkkkkk.", ".kkkkkkk.", "tkkkkkkk.", "tt.kkkk..", "...p.p..."]
const birdSit = [BIRD_SIT, [...BIRD_SIT.slice(0, 5), "tkkkkkkk.", "t..kkkk..", BIRD_SIT[7]!], [...BIRD_SIT.slice(0, 5), "kkkkkkkk.", "ttt.kkkk.", BIRD_SIT[7]!]]
export const BIRD = {
  sit: birdSit,
  blink: [shut(BIRD_SIT)],
  groom: [shut(BIRD_SIT), shut(birdSit[1]!)],
  walk: [BIRD_SIT, hop(BIRD_SIT), birdSit[1]!, hop(birdSit[1]!)],
  sleep: [[".........", "...kkkk..", "..kkckkp.", ".kkkkkkk.", "tkkkkkkk.", ".kkkkkk.."], [".........", ".........", "..kkckkp.", ".kkkkkkk.", "tkkkkkkk.", ".kkkkkk.."]],
  play: [hop(BIRD_SIT), BIRD_SIT],
  stretch: [["....kkk..", "...kkekp.", "kk.kkkk..", "kkkkkkkk.", ".kkkkkkk.", "tkkkkkkk.", "tt.kkkk..", "...p.p..."]],
}

/** the art the cat slot's species draws with */
export const SPECIES_ART = { cat: CAT, rabbit: RABBIT, bird: BIRD }

// Argos, the office dog (Borges' "The Immortal"), facing right: coat (k), ears (e), eye (i), nose
// (n), tongue (p), tail (t), an eye shut (c)
export const DOG = {
  // sitting up, tongue out, tail going
  sit: [[".........ee.....", "........eekkk...", "........ekkikk..", "........kkkkkkkn", "........kkkkkpp.", ".......kkkkk..p.", "......kkkkkk....", "t....kkkkkkk....", ".t..kkkkkkkk....", "..tkkkkk.k.k...."],
        [".........ee.....", "........eekkk...", "........ekkikk..", "........kkkkkkkn", "........kkkkkpp.", "t......kkkkk..p.", ".t....kkkkkk....", "..t..kkkkkkk....", "....kkkkkkkk....", "...kkkkk.k.k...."]],
  walk: [["...........ee...", "t.........eekkk.", ".t........ekkikk", "..kkkkkkkkkkkkkn", "..kkkkkkkkkkkpp.", "..kkkkkkkkkk....", "..kk.......kk...", ".k..k.....k..k..", "k....k...k....k."],
         ["...........ee...", ".tt.......eekkk.", "...t......ekkikk", "..kkkkkkkkkkkkkn", "..kkkkkkkkkkkpp.", "..kkkkkkkkkk....", "...kk.....kk....", "...k.k....k.k...", "...k..k...k..k.."]],
  // flat out asleep, breathing, an ear twitching
  sleep: [["................", "...........ee...", "..........ekkkk.", "t.kkkkkkkkkckkkn", ".tkkkkkkkkkkkkk.", "kkkkkkkkkkkkkk.."],
          ["................", "............e...", "..kkkkkkk.eekkk.", "t.kkkkkkkkkckkkn", ".tkkkkkkkkkkkkk.", "kkkkkkkkkkkkkk.."]],
  // rolled over for a belly rub, paws going
  belly: [["..k...k...k..k..", "..k..k.....kk...", ".kkkkkkkkkkkkke.", "tkkkkkkkkkkkkcke", ".kkkkkkkkkkkkkkn", "..kkkkkkkkkkkpp."],
          ["...k.k....kk....", "..k...k...k..k..", ".kkkkkkkkkkkkke.", "tkkkkkkkkkkkkcke", ".kkkkkkkkkkkkkkn", "..kkkkkkkkkkkpp."]],
}
export const DOG_NAME = "Argos"

/** `over` onto `rows`: a letter paints, `.` leaves the pixel, `_` clears it; `behind` paints only the clear pixels */
function overlay(rows: string[], over: View | undefined, behind = false) {
  if (!over) return
  for (const [k, o] of Object.entries(over)) {
    const i = Number(k)
    if (!o || i >= rows.length) continue
    const r = rows[i]!.split("")
    for (let c = 0; c < o.length; c++) if (o[c] !== "." && (!behind || r[c] === ".")) r[c] = o[c] === "_" ? "." : o[c]!
    rows[i] = r.join("")
  }
}
/** the look's parts in these slots, painted in the order given */
function wear(rows: string[], look: Look, view: "front" | "side" | "back", slots: Slot[]) {
  for (const slot of slots) {
    const spec = look.parts?.[slot], gear = spec && gearOf(spec)
    if (gear) overlay(rows, gear[view], slot === "back" && view !== "back")
  }
}

/** a figure (`heightOf` rows, 20 for the average build; 14 seated), facing `face` */
export function figure(look: Look, archetype: string | null | undefined, lead: boolean, boss: boolean, face: Dir, pose: Pose, step: number, shut: boolean): string[] {
  const view = face === "up" ? "back" : face === "left" || face === "right" ? "side" : "front"
  const bald = look.hair === "bald"
  const body = BODY[bodyOf(look)]
  let rows: string[]
  if (look.custom?.[view]) {
    rows = [...look.custom[view]!]
  } else if (view === "side") {
    rows = SIDE_HEAD.map((r, i) => (SIDE_BARE.has(look.hair) && i >= 2 && i <= 7 ? r.replaceAll("h", "f") : r))
    overlay(rows, SIDE_OVER[look.hair])
    rows.push(...body.sideTorso, ...(pose !== "stand" ? body.legs.sideStand! : step === 0 ? body.legs.sideStand! : step === 1 ? body.legs.sideA! : body.legs.sideB!))
  } else {
    const top = [...TOP[look.hair]]
    let face4 = [...FACE]
    if (view === "back") {
      const h = bald ? "f" : "h"
      top[5] = look.hair === "long" ? ".hhhhhhhhhh." : `..${h.repeat(8)}..`
      face4 = [`..${h.repeat(8)}..`, `..${h.repeat(8)}..`, `...${h.repeat(6)}...`, ".....ff....."]
      if (look.hair === "long") face4 = [".hhhhhhhhhh.", ".hhhhhhhhhh.", ".hhhhhhhhhh.", ".....ff....."]
    } else {
      if (shut) face4[0] = SHUT
      if (look.hair === "long") face4 = face4.map((r, i) => (i < 3 ? `.h${r.slice(2, 10)}h.` : r))
      if (bald) face4[1] = "..ffhhhhff.." // the mustache
    }
    rows = [...top, ...face4, ...body.torso, ...(pose === "couch" ? body.legs.couch! : step === 1 ? body.legs.a! : step === 2 ? body.legs.b! : body.legs.stand!)]
  }
  if (look.outfit) overlay(rows, view === "front" ? OUTFIT[look.outfit].front : view === "back" ? OUTFIT[look.outfit].back : OUTFIT[look.outfit].side)
  wear(rows, look, view, ["back", "neck", "mouth"])
  if (look.accessory) overlay(rows, view === "front" ? ACCESSORY[look.accessory].front : view === "back" ? ACCESSORY[look.accessory].back : ACCESSORY[look.accessory].side)
  wear(rows, look, view, ["eyes", "head", "hand"])
  const gear = GEAR[archetype ?? ""]
  overlay(rows, view === "front" ? gear?.front : view === "back" ? gear?.back : gear?.side)
  if (view === "front" && lead) overlay(rows, BADGE)
  if (view === "front" && boss) overlay(rows, TIE)
  if (face === "right") rows = rows.map((r) => r.split("").reverse().join(""))
  return pose === "sit" ? rows.slice(0, 14) : rows
}

export function lookOf(name: string): Look {
  const h = hash(name)
  return {
    hair: HAIRS[h % HAIRS.length]!,
    hairRole: HAIR_ROLES[(h >>> 4) % HAIR_ROLES.length]!,
    decor: (h >>> 8) % DECOR.length,
    fav: (["board", "couch", "cooler", "coffee"] as Fav[])[(h >>> 12) % 4]!,
    emote: SIGNATURES[(h >>> 16) % SIGNATURES.length]!,
    slow: ((h >>> 20) & 1) === 1,
    blink: (h >>> 22) % 50,
  }
}
/** a seeded roll of the new look fields: a build, and in each slot a part (or none) with its dials; lookOf never calls it */
export function rollLook(seed: string): Pick<Look, "body" | "parts"> {
  const pick = <T>(xs: readonly T[], key: string) => xs[hash(seed + key) % xs.length]!
  const parts: NonNullable<Look["parts"]> = {}
  for (const slot of SLOTS) {
    const ids = idsIn(slot), n = hash(seed + slot) % (ids.length + 1)
    if (n === ids.length) continue
    const id = ids[n]!
    parts[slot] = { id, dials: Object.fromEntries(Object.entries(PARTS[id]!.dials).map(([k, opts]) => [k, pick(opts, slot + k)])) }
  }
  return { body: pick(BODIES, "body"), parts }
}
export const BOSS_LOOK: Look = { hair: "mop", hairRole: "structure", decor: 1, fav: "board", emote: "…", slow: false, blink: 7 }

/** a figure's paint map: hair, skin, ink, shirt (its archetype's colour), trousers, boots, gear */
export function paints(shirt: string, look: Look): Record<string, string> {
  return { h: ROLE[look.hairRole], f: look.skinRole ? ROLE[look.skinRole] : ROLE.prose, k: ROLE.fieldInk, s: shirt, p: ROLE.meta, b: ROLE.structure, y: ROLE.body, c: ROLE.structure, g: ROLE.key, e: ROLE.key, w: ROLE.prose, r: ROLE.alarm, o: ROLE.body }
}
/** an archetype's colour (its shirt, its sticky): its role if it has one, else gold */
export const shirtOf = (archetype?: string | null) => ROLE[(archetype ?? "") as Role] ?? ROLE.body
