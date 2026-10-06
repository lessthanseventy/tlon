// The office's people and things as sprites: one char per pixel, "." clear; letters are looked up
// in a paint map at draw time, so every colour is a ROLE. Looks and habits come from a hash of the
// agent's name, gear from its archetype — the same person looks the same in every room.
import { ROLE, type Role } from "./palette"

export type Dir = "down" | "up" | "left" | "right"
export type Pose = "stand" | "sit" | "couch"
/** where someone likes to idle */
export type Fav = "board" | "couch" | "cooler" | "coffee"
export type Hair = "mop" | "spiky" | "bun" | "long" | "bald"
export type Look = { hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number }

export function hash(s: string) { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0 }

const HAIRS: Hair[] = ["mop", "spiky", "bun", "long", "bald"]
const HAIR_ROLES: Role[] = ["inactive", "structure", "meta", "borderInactive"]
const TOP: Record<Hair, string[]> = {
  mop: ["............", "............", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  spiky: ["............", "...h..h..h..", "..hhhhhhhh..", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  bun: [".....hh.....", "....hhhh....", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
  long: ["............", "............", "...hhhhhh...", "..hhhhhhhh..", ".hhhhhhhhhh.", ".hhffffffhh."],
  bald: ["............", "............", "............", "...ffffff...", "..ffffffff..", "..ffffffff.."],
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
// archetype gear, as row overlays per view
type Gear = { front?: Record<number, string>; side?: Record<number, string>; back?: Record<number, string> }
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
  planner: { front: { 11: ".......cc...", 12: "......wwww..", 13: "......wwww..", 14: "......wwww.." }, side: { 11: "..cc........", 12: ".wwww.......", 13: ".wwww......." } },
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

function overlay(rows: string[], over: Record<number, string> | undefined) {
  if (!over) return
  for (const [k, o] of Object.entries(over)) {
    const i = Number(k), r = rows[i]!.split("")
    for (let c = 0; c < o.length; c++) if (o[c] !== ".") r[c] = o[c]!
    rows[i] = r.join("")
  }
}

/** a 20-row figure (or 14 rows seated), facing `face` */
export function figure(look: Look, archetype: string | null | undefined, lead: boolean, boss: boolean, face: Dir, pose: Pose, step: number, shut: boolean): string[] {
  const view = face === "up" ? "back" : face === "left" || face === "right" ? "side" : "front"
  const bald = look.hair === "bald"
  let rows: string[]
  if (view === "side") {
    rows = SIDE_HEAD.map((r, i) => (bald && i >= 2 && i <= 7 ? r.replaceAll("h", "f") : r))
    if (look.hair === "bun") overlay(rows, { 0: ".......hh...", 1: "......hhhh.." })
    if (look.hair === "spiky") overlay(rows, { 1: "....h.h.h..." })
    rows.push(...SIDE_TORSO, ...(pose !== "stand" ? LEGS.sideStand! : step === 0 ? LEGS.sideStand! : step === 1 ? LEGS.sideA! : LEGS.sideB!))
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
    rows = [...top, ...face4, ...TORSO, ...(pose === "couch" ? LEGS.couch! : step === 1 ? LEGS.a! : step === 2 ? LEGS.b! : LEGS.stand!)]
  }
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
export const BOSS_LOOK: Look = { hair: "mop", hairRole: "structure", decor: 1, fav: "board", emote: "…", slow: false, blink: 7 }

/** a figure's paint map: hair, skin, ink, shirt (its archetype's colour), trousers, boots, gear */
export function paints(shirt: string, look: Look): Record<string, string> {
  return { h: ROLE[look.hairRole], f: ROLE.prose, k: ROLE.fieldInk, s: shirt, p: ROLE.meta, b: ROLE.structure, y: ROLE.body, c: ROLE.structure, g: ROLE.key, e: ROLE.key, w: ROLE.prose, r: ROLE.alarm }
}
/** an archetype's colour (its shirt, its sticky): its role if it has one, else gold */
export const shirtOf = (archetype?: string | null) => ROLE[(archetype ?? "") as Role] ?? ROLE.body
