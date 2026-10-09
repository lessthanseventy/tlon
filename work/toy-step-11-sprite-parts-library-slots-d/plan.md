# Toy step 11 — sprite parts library: plan

Ticket #67 (thread 220). No `spec.md` exists for this workline, so the three decisions the ticket
asked a spec to make are made here; hronir reads them before build. All paths under `office/`.
Gate: `mise run office:check` (typecheck + `bun test` at 03:00 and 15:00) — run **unsandboxed**; in the
sandbox `terminal.test.ts` (tmux) fails and `cli.test.ts` needs `bun install` for `pngjs` (both are the
environment, not this work). Per task: `cd office && bun test test/<file>`.

## Decisions (say so if wrong)

1. **Layer order** (painted first → last): body → *back* part → outfit → *neck* → *mouth* (moustache,
   beard) → legacy `accessory` → *eyes* → *head* (hat) → *hand* → archetype gear → lead badge → tie.
   A hat does not drop the hair: its overlay uses `_` (clear) for every pixel above its brim row and
   beside its crown, so bun knots and spiky tips vanish under it while the fringe below the brim stays.
   Archetype gear (hard hat, safari hat…) still paints last — identity beats a personal hat.
2. **Body shapes keep 12-wide rows and the torso rows 10–14**, so every overlay table stays valid. A
   shape differs only in torso width (`round`: 12 wide) and leg rows (`tall` 7, `short` 3, average 5):
   figure height is 22 / 18 / 20, drawn once per shape in the `BODY` table (walk frames included).
   `heightOf(look)` gives the height; `draw.ts` anchors on it instead of the literal 20. A look with
   `custom` keeps the average build (custom views are 20 tall). Seated (14 rows) is the same on all shapes.
3. **New Look fields are data**: `body?: Body` and `parts?: Partial<Record<Slot, {id, dials?}>>` — one
   part per slot, slots `head eyes mouth neck back hand`. `PARTS` in the new `kit/parts.ts` maps id →
   `{slot, dials (name → options), draw(dials) → {front,side,back} row overlays}`; `figure()` loops slots,
   no `if (look.hat === …)`. Unset or unoffered dials fall to the first option; an unknown id (stale
   looks.json) draws nothing. `lookOf` is **untouched** and never returns `body`/`parts`; `HAIRS` stays
   5 long (a name hashes to an index into it) and the new styles live in `HAIR_STYLES`. `rollLook(seed)`
   rolls body + parts + dials explicitly (look card `r` key); nothing rolls them implicitly, so every
   existing actor draws byte-identically. Task 0 pins that with a hash.
4. Legacy `Accessory` (glasses, headphones) and `Outfit` stay as they are; the `glasses` *part* (dials
   frame/tint) draws the same pixels at its defaults. Migrating `accessory` into parts is a follow-up.
5. Out (follow-ups): model-drawn parts (#59), the weird end (duck hat…), editing individual dials on the
   look card (it cycles part ids and rolls), the bald-mustache hack in `figure()` stays (stable looks).
6. #83 / fire drill: `rg "fire|panic" kit/sprites.ts` is empty on main and `work/toy-the-office-is-on-fire-…`
   does not touch `kit/sprites.ts`; the drill is a line in `sim.ts`. No conflict expected.

Order: 0 → 1 → 2 → 3 → 4. One commit per task; each leaves the gate green.

## Task 0 — freeze today's people (test only, green on current code)

Create `test/stable.test.ts`. The hash was computed from `main` before any change; it must pass now and
after every later task (if a later task turns it red, that task changed an existing person — fix the task).

```ts
// Today's people must not change: the figures every existing look draws, hashed once from the code
// before the parts library, and the hair and hair colour each name rolls.
import { describe, expect, test } from "bun:test"
import { createHash } from "node:crypto"
import { figure, HAIRS, lookOf, type Look } from "../kit/sprites"

describe("existing looks are stable", () => {
  test("every name, archetype, view, pose, step and gear draws the same pixels as before the library", () => {
    const out: string[] = []
    const names = ["tertius", "hronir", "lonnrot", "yu", "ashe", "daneri", "quain", "uqbar", "w0", "w1", "a", "b"]
    const archetypes = [null, "builder", "surveyor", "reviewer", "assistant", "researcher", "librarian", "planner"]
    const extras: Partial<Look>[] = [{}, { outfit: "hoodie" }, { outfit: "labcoat" }, { accessory: "glasses" }, { accessory: "headphones" }]
    for (const n of names) for (const arch of archetypes) for (const face of ["down", "up", "left", "right"] as const)
      for (const pose of ["stand", "sit", "couch"] as const) for (const step of [0, 1, 2]) for (const shut of [false, true])
        for (const lead of [false, true]) for (const x of extras)
          out.push(figure({ ...lookOf(n), ...x }, arch, lead, lead, face, pose, step, shut).join("|"))
    for (const h of HAIRS) out.push(figure({ ...lookOf("x"), hair: h }, null, false, false, "left", "stand", 0, false).join("|"))
    expect(out.length).toBe(69125)
    expect(createHash("sha256").update(out.join("\n")).digest("hex")).toBe("8169b02dc6d3c7d24fc09d713448db32ce02d355a23565313efd2b61632fbb24")
  })
  test("a name still hashes to the same hair and hair colour, and to no new field", () => {
    const want: Record<string, [string, string]> = {
      tertius: ["long", "meta"], hronir: ["mop", "inactive"], lonnrot: ["bun", "borderInactive"], yu: ["mop", "structure"],
      ashe: ["spiky", "meta"], daneri: ["bun", "inactive"], quain: ["mop", "meta"], uqbar: ["mop", "structure"],
    }
    for (const [n, [hair, hairRole]] of Object.entries(want)) {
      const l = lookOf(n)
      expect([l.hair, l.hairRole]).toEqual([hair, hairRole])
      expect(l.body).toBeUndefined()
      expect(l.parts).toBeUndefined()
    }
  })
})
```
Verify: `bun test test/stable.test.ts` → 2 pass. Commit: `office: pin today's figures and name→hair mapping`.

## Task 1 — body shapes

Test first: `test/bodies.test.ts` (red: no `body`, `heightOf`, `BODIES`).

```ts
import { describe, expect, test } from "bun:test"
import { BODIES, figure, heightOf, lookOf, type Look } from "../kit/sprites"

describe("body shapes", () => {
  const look = (body: Look["body"]): Look => ({ ...lookOf("yu"), body })
  test("tall and short change only the legs; every shape is 12 wide", () => {
    const avg = figure(look("average"), null, false, false, "down", "stand", 0, false)
    expect(avg.length).toBe(20)
    for (const [b, h] of [["tall", 22], ["short", 18], ["round", 20]] as const) {
      const f = figure(look(b), null, false, false, "down", "stand", 0, false)
      expect(f.length).toBe(h)
      expect(heightOf(look(b))).toBe(h)
      expect(f.every((r) => r.length === 12)).toBe(true)
      if (b !== "round") expect(f.slice(0, 15)).toEqual(avg.slice(0, 15))
    }
    expect(figure(look("round"), null, false, false, "down", "stand", 0, false)[11]).toContain("ssssssssssss")
  })
  test("every shape draws every view and walk frame at its height, seated at 14", () => {
    for (const b of BODIES) for (const face of ["down", "up", "left", "right"] as const) for (const step of [0, 1, 2]) {
      expect(figure(look(b), "builder", true, false, face, "stand", step, false).length).toBe(heightOf(look(b)))
      expect(figure(look(b), null, false, false, face, "sit", step, false).length).toBe(14)
    }
  })
  test("a custom look keeps the average build", () => {
    expect(heightOf({ ...look("tall"), custom: { front: Array(20).fill(".".repeat(12)) } })).toBe(20)
  })
})
```

Edit `kit/sprites.ts` to match (adds `Body`, `BODIES`, `BODY` table, `bodyOf`, `heightOf`; figure() reads the table):

```diff
--- s0.ts	2026-10-09 13:27:30.276804819 -0600
+++ s1.ts	2026-10-09 13:27:30.332645121 -0600
@@ -8,11 +8,13 @@
 /** where someone likes to idle */
 export type Fav = "board" | "couch" | "cooler" | "coffee"
 export type Hair = "mop" | "spiky" | "bun" | "long" | "bald"
+export type Body = "average" | "tall" | "short" | "round"
 export type Outfit = "hoodie" | "labcoat"
 export type Accessory = "glasses" | "headphones"
 export type Look = {
   hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number
   skinRole?: Role; outfit?: Outfit; accessory?: Accessory
+  body?: Body
   custom?: Partial<Record<"front" | "side" | "back", string[]>>
 }
 export const SKIN_ROLES: Role[] = ["builder", "surveyor", "reviewer", "assistant", "planner", "body"]
@@ -42,6 +44,47 @@
   sideA: ["...pppppp...", "...pp..pp...", "..pp....pp..", ".pp......pp.", ".bb......bb."],
   sideB: ["...pppppp...", "....pppp....", "....pppp....", "....pp.p....", "...bbbbb...."],
 }
+/** body shapes: all 12 wide, with the torso rows (10-14) in place so every overlay below stays valid;
+ * a shape differs in its torso's width and in how many leg rows it stands on (tall 7, short 3), so
+ * its walk and sit frames are drawn here once */
+export const BODIES: Body[] = ["average", "tall", "short", "round"]
+const BODY: Record<Body, { torso: string[]; sideTorso: string[]; legs: Record<string, string[]> }> = {
+  average: { torso: TORSO, sideTorso: SIDE_TORSO, legs: LEGS },
+  round: {
+    torso: [".ssssssssss.", "ssssssssssss", "ssssssssssss", "fssssssssssf", ".ssssssssss."],
+    sideTorso: ["..ssssssss..", "..ssssssss..", "..sfssssss..", "..ssssssss..", "..ssssssss.."],
+    legs: LEGS,
+  },
+  tall: {
+    torso: TORSO, sideTorso: SIDE_TORSO,
+    legs: {
+      stand: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..bb....bb.."],
+      a: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..bb....pp..", "........bb.."],
+      b: ["..pppppppp..", "..ppp..ppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..pp....bb..", "..bb........"],
+      couch: ["..pppppppp..", "..pppppppp..", "..pp....pp..", "..pp....pp..", "..pp....pp..", "..bb....bb..", "............"],
+      sideStand: ["...pppppp...", "....pppp....", "....pp.p....", "....pp.p....", "....pp.p....", "....pp.p....", "...bbb.bb..."],
+      sideA: ["...pppppp...", "...pp..pp...", "..pp....pp..", "..pp....pp..", ".pp......pp.", ".pp......pp.", ".bb......bb."],
+      sideB: ["...pppppp...", "....pppp....", "....pppp....", "....pppp....", "....pp.p....", "....pp.p....", "...bbbbb...."],
+    },
+  },
+  short: {
+    torso: TORSO, sideTorso: SIDE_TORSO,
+    legs: {
+      stand: ["..pppppppp..", "..pp....pp..", "..bb....bb.."],
+      a: ["..pppppppp..", "..bb....pp..", "........bb.."],
+      b: ["..pppppppp..", "..pp....bb..", "..bb........"],
+      couch: ["..pppppppp..", "..pppppppp..", "..bb....bb.."],
+      sideStand: ["...pppppp...", "....pp.p....", "...bbb.bb..."],
+      sideA: ["...pppppp...", "..pp....pp..", ".bb......bb."],
+      sideB: ["...pppppp...", "....pppp....", "...bbbbb...."],
+    },
+  },
+}
+/** custom views are drawn 20 tall, so a custom look keeps the average build for its generated views */
+const bodyOf = (look: Look): Body => (look.custom ? "average" : look.body ?? "average")
+/** rows a standing figure of this look is tall: where its head sits above its feet */
+export const heightOf = (look: Look) => 15 + BODY[bodyOf(look)].legs.stand!.length
+
 // archetype gear, as row overlays per view
 type Gear = { front?: Record<number, string>; side?: Record<number, string>; back?: Record<number, string> }
 const HARDHAT = { 1: "....yyyy....", 2: "..yyyyyyyy..", 3: ".yyyyyyyyyy." }
@@ -208,10 +251,11 @@
   }
 }
 
-/** a 20-row figure (or 14 rows seated), facing `face` */
+/** a figure (`heightOf` rows, 20 for the average build; 14 seated), facing `face` */
 export function figure(look: Look, archetype: string | null | undefined, lead: boolean, boss: boolean, face: Dir, pose: Pose, step: number, shut: boolean): string[] {
   const view = face === "up" ? "back" : face === "left" || face === "right" ? "side" : "front"
   const bald = look.hair === "bald"
+  const body = BODY[bodyOf(look)]
   let rows: string[]
   if (look.custom?.[view]) {
     rows = [...look.custom[view]!]
@@ -219,7 +263,7 @@
     rows = SIDE_HEAD.map((r, i) => (bald && i >= 2 && i <= 7 ? r.replaceAll("h", "f") : r))
     if (look.hair === "bun") overlay(rows, { 0: ".......hh...", 1: "......hhhh.." })
     if (look.hair === "spiky") overlay(rows, { 1: "....h.h.h..." })
-    rows.push(...SIDE_TORSO, ...(pose !== "stand" ? LEGS.sideStand! : step === 0 ? LEGS.sideStand! : step === 1 ? LEGS.sideA! : LEGS.sideB!))
+    rows.push(...body.sideTorso, ...(pose !== "stand" ? body.legs.sideStand! : step === 0 ? body.legs.sideStand! : step === 1 ? body.legs.sideA! : body.legs.sideB!))
   } else {
     const top = [...TOP[look.hair]]
     let face4 = [...FACE]
@@ -233,7 +277,7 @@
       if (look.hair === "long") face4 = face4.map((r, i) => (i < 3 ? `.h${r.slice(2, 10)}h.` : r))
       if (bald) face4[1] = "..ffhhhhff.." // the mustache
     }
-    rows = [...top, ...face4, ...TORSO, ...(pose === "couch" ? LEGS.couch! : step === 1 ? LEGS.a! : step === 2 ? LEGS.b! : LEGS.stand!)]
+    rows = [...top, ...face4, ...body.torso, ...(pose === "couch" ? body.legs.couch! : step === 1 ? body.legs.a! : step === 2 ? body.legs.b! : body.legs.stand!)]
   }
   if (look.outfit) overlay(rows, view === "front" ? OUTFIT[look.outfit].front : view === "back" ? OUTFIT[look.outfit].back : OUTFIT[look.outfit].side)
   if (look.accessory) overlay(rows, view === "front" ? ACCESSORY[look.accessory].front : view === "back" ? ACCESSORY[look.accessory].back : ACCESSORY[look.accessory].side)
```

Edit `kit/draw.ts` (`drawActors`): import `heightOf` from `./sprites`; line 83 `actor.y - 20` → `actor.y - heightOf(actor.look)`
(keep the `+ (actor.moving && step === 2 ? -1 : 0)`), and line 138 `h: sitting ? 14 : 20` → `h: sitting ? 14 : heightOf(actor.look)`.
Add to `test/bodies.test.ts` nothing more — draw.ts is covered by the golden frames (unchanged for average).

Verify: `bun test test/bodies.test.ts test/stable.test.ts test/wide.test.ts` green (golden.json must NOT change: average
is the default). Commit: `office: body shapes — tall, short, round, drawn once`.

## Task 2 — more hair styles and outfits

Test first: `test/hair.test.ts` (red: no `HAIR_STYLES`, no new outfits).

```ts
import { describe, expect, test } from "bun:test"
import { figure, HAIR_STYLES, lookOf, OUTFIT } from "../kit/sprites"

describe("more hair and outfits", () => {
  test("every style draws in every view, 12 wide, and the new ones differ from the old", () => {
    for (const h of HAIR_STYLES) for (const face of ["down", "up", "left"] as const) {
      const f = figure({ ...lookOf("x"), hair: h }, null, false, false, face, "stand", 0, false)
      expect(f.length).toBe(20)
      expect(f.every((r) => r.length === 12)).toBe(true)
    }
    const front = HAIR_STYLES.map((h) => figure({ ...lookOf("x"), hair: h }, null, false, false, "down", "stand", 0, false).slice(0, 6).join())
    expect(new Set(front).size).toBe(HAIR_STYLES.length)
  })
  test("every outfit has three views of 12-wide rows on the neck and torso rows", () => {
    for (const o of Object.values(OUTFIT)) for (const v of [o.front, o.side, o.back]) {
      expect(v).toBeDefined()
      for (const [r, s] of Object.entries(v!)) expect(Number(r) >= 9 && Number(r) <= 14 && s!.length === 12).toBe(true)
    }
  })
})
```

Edit `kit/sprites.ts` to match (three styles as data rows, the two `if (look.hair === …)` side-view branches become the `SIDE_OVER`/`SIDE_BARE` tables, three outfits):

```diff
--- s1.ts	2026-10-09 13:27:30.332645121 -0600
+++ s2.ts	2026-10-09 13:27:30.334804193 -0600
@@ -7,9 +7,9 @@
 export type Pose = "stand" | "sit" | "couch"
 /** where someone likes to idle */
 export type Fav = "board" | "couch" | "cooler" | "coffee"
-export type Hair = "mop" | "spiky" | "bun" | "long" | "bald"
+export type Hair = "mop" | "spiky" | "bun" | "long" | "bald" | "curly" | "mohawk" | "parted"
 export type Body = "average" | "tall" | "short" | "round"
-export type Outfit = "hoodie" | "labcoat"
+export type Outfit = "hoodie" | "labcoat" | "apron" | "suit" | "poncho"
 export type Accessory = "glasses" | "headphones"
 export type Look = {
   hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number
@@ -21,7 +21,10 @@
 
 export function hash(s: string) { let h = 2166136261; for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619); return h >>> 0 }
 
+/** the styles lookOf rolls from: fixed, because a name hashes to an index into it */
 export const HAIRS: Hair[] = ["mop", "spiky", "bun", "long", "bald"]
+/** every style, for the look card and rollLook; lookOf never picks past HAIRS */
+export const HAIR_STYLES: Hair[] = [...HAIRS, "curly", "mohawk", "parted"]
 export const HAIR_ROLES: Role[] = ["inactive", "structure", "meta", "borderInactive"]
 const TOP: Record<Hair, string[]> = {
   mop: ["............", "............", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
@@ -29,6 +32,18 @@
   bun: [".....hh.....", "....hhhh....", "....hhhh....", "..hhhhhhhh..", "..hhhhhhhh..", "..hffffffh.."],
   long: ["............", "............", "...hhhhhh...", "..hhhhhhhh..", ".hhhhhhhhhh.", ".hhffffffhh."],
   bald: ["............", "............", "............", "...ffffff...", "..ffffffff..", "..ffffffff.."],
+  curly: ["............", "...hhhhhh...", "..hhhhhhhh..", ".hhhhhhhhhh.", ".hhhhhhhhhh.", "..hffffffh.."],
+  mohawk: ["............", ".....hh.....", "....hhhh....", "...fhhhhf...", "..ffhhhhff..", "..ffffffff.."],
+  parted: ["............", "...hhhhh....", "..hhhhhhhh..", "..hhhfhhhh..", "..hhhhhhhh..", "..hffffffh.."],
+}
+/** hairless from the side (the hair's own rows turn to skin) before its overlay */
+const SIDE_BARE = new Set<Hair>(["bald", "mohawk"])
+/** a style's side-view rows over SIDE_HEAD */
+const SIDE_OVER: Partial<Record<Hair, Record<number, string>>> = {
+  bun: { 0: ".......hh...", 1: "......hhhh.." },
+  spiky: { 1: "....h.h.h..." },
+  curly: { 1: "....hhhhh...", 2: "...hhhhhhhh.", 3: "..hhhhhhhhhh" },
+  mohawk: { 1: "....hhh.....", 2: "....hhhh....", 3: "....hhhh...." },
 }
 const FACE = ["..fkffffkf..", "..ffffffff..", "...ffkkff...", ".....ff....."]
 const SHUT = "..fkkffkkf.."
@@ -103,6 +118,9 @@
   planner: { front: { 11: ".......cc...", 12: "......wwww..", 13: "......wwww..", 14: "......wwww.." }, side: { 11: "..cc........", 12: ".wwww.......", 13: ".wwww......." } },
 }
 export const OUTFIT: Record<Outfit, Gear> = {
+  apron: { front: { 11: "...wwwwww...", 12: "...wwwwww...", 13: "...wwwwww...", 14: "...wwwwww..." }, back: { 11: ".....ww.....", 12: ".....ww....." }, side: { 11: "...wwww.....", 12: "...wwww.....", 13: "...wwww.....", 14: "...wwww....." } },
+  suit: { front: { 10: "..kk....kk..", 11: "..kk.ww.kk..", 12: "..kkk..kkk..", 13: "..kkk..kkk.." }, back: { 10: ".kkkkkkkkkk.", 11: ".kkkkkkkkkk.", 12: ".kkkkkkkkkk." }, side: { 10: "...kkkkkk...", 11: "...kkkkkk...", 12: "...kkkkkk..." } },
+  poncho: { front: { 10: ".rrrrrrrrrr.", 11: "rrrrrrrrrrrr", 12: "rr.rrrrrr.rr" }, back: { 10: ".rrrrrrrrrr.", 11: "rrrrrrrrrrrr", 12: "rr.rrrrrr.rr" }, side: { 10: "..rrrrrrrr..", 11: "..rrrrrrrr..", 12: "..rrrrrrrr.." } },
   hoodie: { front: { 10: ".oooooooooo.", 11: ".oo........o" }, back: { 10: ".oooooooooo." }, side: { 10: "..oooooooo.." } },
   labcoat: { front: { 9: ".wwwwwwwwww.", 10: "ww........ww", 11: "ww........ww" }, back: { 9: ".wwwwwwwwww." }, side: { 9: "wwwwwwwwwwww" } },
 }
@@ -260,9 +278,8 @@
   if (look.custom?.[view]) {
     rows = [...look.custom[view]!]
   } else if (view === "side") {
-    rows = SIDE_HEAD.map((r, i) => (bald && i >= 2 && i <= 7 ? r.replaceAll("h", "f") : r))
-    if (look.hair === "bun") overlay(rows, { 0: ".......hh...", 1: "......hhhh.." })
-    if (look.hair === "spiky") overlay(rows, { 1: "....h.h.h..." })
+    rows = SIDE_HEAD.map((r, i) => (SIDE_BARE.has(look.hair) && i >= 2 && i <= 7 ? r.replaceAll("h", "f") : r))
+    overlay(rows, SIDE_OVER[look.hair])
     rows.push(...body.sideTorso, ...(pose !== "stand" ? body.legs.sideStand! : step === 0 ? body.legs.sideStand! : step === 1 ? body.legs.sideA! : body.legs.sideB!))
   } else {
     const top = [...TOP[look.hair]]
```

Edit `tui/main.ts` (look card, ~line 1193): `cycleVal(HAIRS, …)` → `cycleVal(HAIR_STYLES, …)`; import `HAIR_STYLES`
(drop `HAIRS` from that import if now unused). The outfit row already cycles `Object.keys(OUTFIT)`.
Verify: `bun test test/hair.test.ts test/stable.test.ts` green (stable proves the refactored branches are pixel-identical). Commit: `office: curly, mohawk, parted hair; apron, suit, poncho`.

## Task 3 — the parts library

Create `kit/parts.ts` (complete; 21 parts across 6 slots; every part drawn once per view; dials as options):

```ts
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
```

Test first: `test/parts.test.ts` (red until `kit/parts.ts` and the sprites edit exist). It is the data gate: every part at
every dial combination has all three views, 12-wide rows, real row numbers (0–17), only its slot's letters; the
letters outside the body clear 3:1 on `ground/panel/raised/edge` (the skin-role check's backgrounds — if a hue
ever fails, drop it from `HUES`); old glasses unchanged; a seeded roll renders every view and walk frame.

```ts
import { describe, expect, test } from "bun:test"
import { contrast, ROLE } from "../kit/palette"
import { dialsOf, gearOf, idsIn, nextPart, PARTS, PART_IDS, SLOTS, type DialVals, type Slot } from "../kit/parts"
import { BODIES, figure, heightOf, lookOf, paints, rollLook, type Dir, type Look } from "../kit/sprites"

/** every combination of a part's dials */
function combos(id: string): DialVals[] {
  return Object.entries(PARTS[id]!.dials).reduce<DialVals[]>((acc, [k, opts]) => acc.flatMap((a) => opts.map((o) => ({ ...a, [k]: o }))), [{}])
}
// the letters a slot may paint: outside the body they sit on the room, so only roles that clear 3:1
const LETTERS: Record<Slot, string> = { head: "rgywc_.", neck: "rgywc.", back: "rgywc.", hand: "rgywc.", eyes: "kgryw.", mouth: "h." }

describe("the parts library is well-formed", () => {
  test("every slot has parts, and every part names its slot", () => {
    for (const s of SLOTS) expect(idsIn(s).length).toBeGreaterThanOrEqual(2)
    expect(PART_IDS.length).toBeGreaterThanOrEqual(21)
  })
  test("every part, at every dial setting, has all three views of 12-wide rows on real row numbers, in its slot's letters", () => {
    for (const id of PART_IDS) for (const d of combos(id)) {
      const g = PARTS[id]!.draw(d), ok = new RegExp(`^[${LETTERS[PARTS[id]!.slot]!.replace(".", "\\.")}]{12}$`)
      for (const view of ["front", "side", "back"] as const) {
        expect(g[view]).toBeDefined()
        for (const [row, s] of Object.entries(g[view])) {
          const n = Number(row)
          expect({ id, d, view, row, ok: Number.isInteger(n) && n >= 0 && n <= 17 && s!.length === 12 && ok.test(s!) }).toMatchObject({ ok: true })
        }
      }
    }
  })
  test("each part draws something in the front and side views", () => {
    for (const id of PART_IDS) for (const view of ["front", "side"] as const) expect(Object.keys(PARTS[id]!.draw(dialsOf(PARTS[id]!, {}))[view]).length).toBeGreaterThan(0)
  })
  test("the paint letters clear 3:1 on every room background, like the skin roles", () => {
    const paint = paints("#fff", lookOf("x"))
    for (const slot of ["head", "neck", "back", "hand"] as const) for (const ch of LETTERS[slot].replace(/[._]/g, "")) {
      for (const bg of [ROLE.ground, ROLE.panel, ROLE.raised, ROLE.edge]) expect({ slot, ch, ok: contrast(paint[ch]!, bg) >= 3 }).toMatchObject({ ok: true })
    }
  })
  test("the default glasses are today's glasses", () => {
    expect(gearOf({ id: "glasses" })!.front[6]).toBe("..kk..kk....")
    expect(gearOf({ id: "glasses" })!.side[6]).toBe(".kk.........")
  })
})

describe("dials", () => {
  test("a missing or unoffered dial value falls back to the first option", () => {
    expect(dialsOf(PARTS.tophat!, { crown: 3, brim: 99 })).toEqual({ hue: "r", crown: 3, brim: 10, band: "none" })
  })
  test("a dial changes the pixels", () => {
    expect(gearOf({ id: "tophat", dials: { crown: 3 } })!.front).not.toEqual(gearOf({ id: "tophat", dials: { crown: 2 } })!.front)
    expect(gearOf({ id: "cape", dials: { length: "long" } })!.back).not.toEqual(gearOf({ id: "cape" })!.back)
  })
  test("an id the library no longer has draws nothing instead of throwing", () => {
    expect(gearOf({ id: "gone" })).toBeUndefined()
    expect(() => figure({ ...lookOf("yu"), parts: { head: { id: "gone" } } }, null, false, false, "down", "stand", 0, false)).not.toThrow()
  })
  test("nextPart walks a slot's parts, then none, then round again", () => {
    const seen: (string | undefined)[] = []
    let cur = nextPart("head", undefined)
    for (let i = 0; i < 20 && cur; i++) { seen.push(cur.id); cur = nextPart("head", cur) }
    expect(seen).toEqual(idsIn("head"))
    expect(nextPart("head", undefined)!.id).toBe(idsIn("head")[0]!)
  })
})

describe("a part on a figure", () => {
  const draw = (look: Look, face: Dir = "down") => figure(look, null, false, false, face, "stand", 0, false)
  test("a hat clears the hair tips under it and paints over the brim row", () => {
    const bare = draw({ ...lookOf("ashe"), hair: "spiky" }), hatted = draw({ ...lookOf("ashe"), hair: "spiky", parts: { head: { id: "tophat" } } })
    expect(bare[1]).toContain("h")
    expect(hatted[1]).not.toContain("h")
    expect(hatted[3]).toBe(".rrrrrrrrrr.")
  })
  test("a cape is behind the body from the front and over it from behind", () => {
    const l = { ...lookOf("yu"), parts: { back: { id: "cape" } } } satisfies Look
    expect(draw(l)[10]).toBe("r.ssssssss.r")
    expect(draw(l, "up")[10]).toBe(".rrrrrrrrrr.")
  })
  test("parts are worn together, one per slot", () => {
    const l: Look = { ...lookOf("yu"), parts: { head: { id: "beanie" }, eyes: { id: "monocle" }, mouth: { id: "beard" }, neck: { id: "scarf" }, back: { id: "wings" }, hand: { id: "mug" } } }
    const worn = draw(l), bare = draw(lookOf("yu"))
    expect(worn.filter((r, i) => r !== bare[i]).length).toBeGreaterThanOrEqual(8)
  })
  test("the hand and neck parts mirror with the figure facing right", () => {
    const l: Look = { ...lookOf("yu"), parts: { hand: { id: "wand" } } }
    expect(draw(l, "right")[13]).toBe([...draw(l, "left")[13]!].reverse().join(""))
  })
})

describe("a seeded roll", () => {
  test("is the same for the same seed, and varied across seeds", () => {
    expect(rollLook("a")).toEqual(rollLook("a"))
    const ids = new Set<string>(), bodies = new Set<string>()
    for (let i = 0; i < 200; i++) { const r = rollLook(`seed${i}`); bodies.add(r.body!); for (const p of Object.values(r.parts!)) ids.add(p.id) }
    expect(bodies.size).toBe(BODIES.length)
    expect(ids.size).toBe(PART_IDS.length)
  })
  test("renders every view, pose and walk frame at the right height", () => {
    for (let i = 0; i < 100; i++) {
      const look: Look = { ...lookOf(`n${i}`), ...rollLook(`seed${i}`) }
      for (const face of ["down", "up", "left", "right"] as const) for (const step of [0, 1, 2]) {
        const f = figure(look, null, false, false, face, "stand", step, false)
        expect(f.length).toBe(heightOf(look))
        expect(f.every((r) => /^[a-z.]{12}$/.test(r))).toBe(true)
        expect(figure(look, null, false, false, face, "sit", step, false).length).toBe(14)
      }
    }
  })
})
```

Edit `kit/sprites.ts` to match (imports parts; `Look.parts`; `overlay` gains `behind` and the `_` clear and skips rows past
the figure; `wear()` paints slots in the layer order above; `rollLook`):

```diff
--- s2.ts	2026-10-09 13:27:30.334804193 -0600
+++ s3.ts	2026-10-09 13:27:30.281668790 -0600
@@ -2,6 +2,7 @@
 // in a paint map at draw time, so every colour is a ROLE. Looks and habits come from a hash of the
 // agent's name, gear from its archetype — the same person looks the same in every room.
 import { ROLE, type Role } from "./palette"
+import { gearOf, idsIn, PARTS, SLOTS, type PartSpec, type Slot, type View } from "./parts"
 
 export type Dir = "down" | "up" | "left" | "right"
 export type Pose = "stand" | "sit" | "couch"
@@ -14,7 +15,7 @@
 export type Look = {
   hair: Hair; hairRole: Role; decor: number; fav: Fav; emote: string; slow: boolean; blink: number
   skinRole?: Role; outfit?: Outfit; accessory?: Accessory
-  body?: Body
+  body?: Body; parts?: Partial<Record<Slot, PartSpec>>
   custom?: Partial<Record<"front" | "side" | "back", string[]>>
 }
 export const SKIN_ROLES: Role[] = ["builder", "surveyor", "reviewer", "assistant", "planner", "body"]
@@ -39,7 +40,7 @@
 /** hairless from the side (the hair's own rows turn to skin) before its overlay */
 const SIDE_BARE = new Set<Hair>(["bald", "mohawk"])
 /** a style's side-view rows over SIDE_HEAD */
-const SIDE_OVER: Partial<Record<Hair, Record<number, string>>> = {
+const SIDE_OVER: Partial<Record<Hair, View>> = {
   bun: { 0: ".......hh...", 1: "......hhhh.." },
   spiky: { 1: "....h.h.h..." },
   curly: { 1: "....hhhhh...", 2: "...hhhhhhhh.", 3: "..hhhhhhhhhh" },
@@ -101,7 +102,7 @@
 export const heightOf = (look: Look) => 15 + BODY[bodyOf(look)].legs.stand!.length
 
 // archetype gear, as row overlays per view
-type Gear = { front?: Record<number, string>; side?: Record<number, string>; back?: Record<number, string> }
+type Gear = { front?: View; side?: View; back?: View }
 const HARDHAT = { 1: "....yyyy....", 2: "..yyyyyyyy..", 3: ".yyyyyyyyyy." }
 const SAFARI = { 1: "...cccccc...", 2: "...cccccc...", 3: "cccccccccccc" }
 const GEAR: Record<string, Gear> = {
@@ -260,14 +261,24 @@
 }
 export const DOG_NAME = "Argos"
 
-function overlay(rows: string[], over: Record<number, string> | undefined) {
+/** `over` onto `rows`: a letter paints, `.` leaves the pixel, `_` clears it; `behind` paints only the clear pixels */
+function overlay(rows: string[], over: View | undefined, behind = false) {
   if (!over) return
   for (const [k, o] of Object.entries(over)) {
-    const i = Number(k), r = rows[i]!.split("")
-    for (let c = 0; c < o.length; c++) if (o[c] !== ".") r[c] = o[c]!
+    const i = Number(k)
+    if (!o || i >= rows.length) continue
+    const r = rows[i]!.split("")
+    for (let c = 0; c < o.length; c++) if (o[c] !== "." && (!behind || r[c] === ".")) r[c] = o[c] === "_" ? "." : o[c]!
     rows[i] = r.join("")
   }
 }
+/** the look's parts in these slots, painted in the order given */
+function wear(rows: string[], look: Look, view: "front" | "side" | "back", slots: Slot[]) {
+  for (const slot of slots) {
+    const spec = look.parts?.[slot], gear = spec && gearOf(spec)
+    if (gear) overlay(rows, gear[view], slot === "back" && view !== "back")
+  }
+}
 
 /** a figure (`heightOf` rows, 20 for the average build; 14 seated), facing `face` */
 export function figure(look: Look, archetype: string | null | undefined, lead: boolean, boss: boolean, face: Dir, pose: Pose, step: number, shut: boolean): string[] {
@@ -297,7 +308,9 @@
     rows = [...top, ...face4, ...body.torso, ...(pose === "couch" ? body.legs.couch! : step === 1 ? body.legs.a! : step === 2 ? body.legs.b! : body.legs.stand!)]
   }
   if (look.outfit) overlay(rows, view === "front" ? OUTFIT[look.outfit].front : view === "back" ? OUTFIT[look.outfit].back : OUTFIT[look.outfit].side)
+  wear(rows, look, view, ["back", "neck", "mouth"])
   if (look.accessory) overlay(rows, view === "front" ? ACCESSORY[look.accessory].front : view === "back" ? ACCESSORY[look.accessory].back : ACCESSORY[look.accessory].side)
+  wear(rows, look, view, ["eyes", "head", "hand"])
   const gear = GEAR[archetype ?? ""]
   overlay(rows, view === "front" ? gear?.front : view === "back" ? gear?.back : gear?.side)
   if (view === "front" && lead) overlay(rows, BADGE)
@@ -318,6 +331,18 @@
     blink: (h >>> 22) % 50,
   }
 }
+/** a seeded roll of the new look fields: a build, and in each slot a part (or none) with its dials; lookOf never calls it */
+export function rollLook(seed: string): Pick<Look, "body" | "parts"> {
+  const pick = <T>(xs: readonly T[], key: string) => xs[hash(seed + key) % xs.length]!
+  const parts: NonNullable<Look["parts"]> = {}
+  for (const slot of SLOTS) {
+    const ids = idsIn(slot), n = hash(seed + slot) % (ids.length + 1)
+    if (n === ids.length) continue
+    const id = ids[n]!
+    parts[slot] = { id, dials: Object.fromEntries(Object.entries(PARTS[id]!.dials).map(([k, opts]) => [k, pick(opts, slot + k)])) }
+  }
+  return { body: pick(BODIES, "body"), parts }
+}
 export const BOSS_LOOK: Look = { hair: "mop", hairRole: "structure", decor: 1, fav: "board", emote: "…", slow: false, blink: 7 }
 
 /** a figure's paint map: hair, skin, ink, shirt (its archetype's colour), trousers, boots, gear */
```

Verify: `bun test test/parts.test.ts test/stable.test.ts test/bodies.test.ts test/hair.test.ts test/sprites.test.ts` green, then `bun run typecheck`.
Commit: `office: the parts library — hats, eyes, mouth, neck, back, hand, with dials and a seeded roll`.

## Task 4 — look card, docs

`tui/main.ts` look card (`case "look"`, rows after `accessory`): import `BODIES`, `rollLook` from `../kit/sprites` and
`nextPart`, `SLOTS` from `../kit/parts`; module-level `let rolls = 0` beside `lookDraft`.

```ts
field("build", draft.body ?? "average", () => { draft.body = cycleVal(BODIES, draft.body ?? "average") }),
...SLOTS.map((slot) => field(slot, draft.parts?.[slot]?.id ?? "none", () => {
  const next = nextPart(slot, draft.parts?.[slot]), parts = { ...draft.parts }
  if (next) parts[slot] = next; else delete parts[slot]
  draft.parts = parts
})),
```
and an action beside `s save`: `{ key: "r", label: "roll", run: () => { Object.assign(draft, rollLook(`${name}:${rolls++}`)); draw() } }`.
`LookOverride` is `Partial<Look>` and looks.json is merged field-wise, so `body`/`parts` save and load with no other change.

Docs in the same commit: `office/AGENTS.md` `kit/` bullet — "sprites and looks (`sprites.ts`)" gains "the parts library (`parts.ts`: slots, dials, `rollLook`)"; add under Law
"**Every worn part is data in `kit/parts.ts`** — a new hat is a `PARTS` entry whose test is the data gate, never a branch in `figure()`; `lookOf` must not gain fields (it would restyle everyone)."
Verify: `mise run office:check` (unsandboxed) green; `mise run check:names` green. Commit: `office: look card edits build and parts; docs`.

## Task 5 — see it (not a code task)

Legible-at-1x is a visual claim the tests can't make. With the `drive-office` skill: write a scratch `looks.json`
(`TLON_LOOKS=…`) giving four sandbox crew names a `rollLook`-style `parts`/`body` (e.g. `{"yu":{"body":"tall","parts":{"head":{"id":"wizard"},"eyes":{"id":"monocle"},"back":{"id":"cape","dials":{"length":"long"}}}}}`),
`mise run office:sandbox`, screenshot the room at 1x and at night (`n`). Look for: hats reading as hats, a beard not
swallowing the face, wings/cape not hidden by `round`, balloon strings reaching the hand. Fix pixel nits as small
commits to `parts.ts` (the data gate keeps them honest) and attach the PNG to the review. Say so plainly if this is
skipped: it would be unverified.

## Reviewer notes
- Task 0's hash is the contract; any red there means an existing actor changed.
- `round` hides cape/backpack edge pixels in the front view (they paint only on clear pixels); intended, cheap.
- Side-view balloon overlaps the nose pixel at the top row for 4-long strings; known, tune by eye in Task 5 or leave.
