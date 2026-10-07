// Argos, the wide room's dog: his data and his day, lifted out of `rooms/wide.ts` so the room's
// own code shrinks to tile composition and chrome. A room still owns his geometry (his bed, his
// bowl, the ping-pong table he watches) — these functions take it as plain data, never `Zones`.
import { balloonLines } from "./canvas"
import { dancing, drawFuss, type Scene } from "./draw"
import { ROLE, tint } from "./palette"
import { FUSS, keyOf, type Actor, type Fussing, type Pt, type Spot } from "./sim"
import { DOG, DOG_NAME } from "./sprites"
import { pick, type Fuss } from "./voices"

/**
 * Argos: where he is, the waypoints he is walking, what he is doing, the row he walks along; what
 * he is saying until `saidUntil`; `belly` the tick his roll-over for a rub ends; `fuss` someone
 * making a fuss of him
 */
export type Dog = { x: number; y: number; aisle: number; path: Pt[]; mode: "walk" | "sit" | "sleep"; until: number; face: number; woof: number; host: string | null; creep: boolean; said: string | null; saidFrom: number; saidUntil: number; belly: number; fuss: Fussing | null; cheer?: boolean }

/**
 * What Argos says, by occasion. He is the troglodyte of Borges' "The Immortal" who turned out to be
 * Homer: an epic poet, mostly forgotten, now overwhelmingly a good boy.
 */
export const ARGOS = {
  pat: ["Good boy? Me? Yes. ME!", "Sing, O Muse, of this scratch behind the ears.", "I have known gods. None pat like you."],
  belly: ["Belly! The WHOLE belly! In twenty-four books!", "Rub the belly and I shall sing of it forever."],
  muse: ["I once sang of Troy. Now I sing of squirrels.", "Rosy-fingered dawn means breakfast, right?", "Wine-dark sea. Water-dark bowl. Same thing.", "Every dog is all dogs. I still want the ball.", "Nine years at Troy. Nine minutes for a walk?", "The Immortal fears nothing. Except the vacuum."],
  test: ["Fetch the tests! FETCH!", "Tests! Can I chase them? Can I?"],
  done: ["Turn's done? WALK? Is it walk time?", "{name} finished! I'm so proud I could howl."],
  queue: ["Someone's waiting! I will guard them.", "{name} needs the boss! I'll fetch!"],
  visit: ["You look like you need a dog, {name}.", "Hello {name}! I brought my whole self."],
  walk: ["WALK!! The best word in any language!", "Every road leads somewhere smelly. I love roads.", "A journey! Like Odysseus, but shorter. Please."],
  office: ["Coming! Coming coming coming.", "Your office! The best office! I'm in it!", "On my way, captain of the crew!"],
  sit: ["Sitting. Very good sitting. Epic, even.", "Look at this sit. Achilles never sat like this.", "Sat. Now treat? Treat now?"],
  bed: ["An epic nap, in twenty-four books.", "Bed. The wine-dark blanket calls.", "I will dream of a thousand squirrels."],
  // you send him over to someone: he tells them so, with his whole body
  cheer: ["{name}! You're doing GREAT! I think! I can't read!", "{name}, I brought you my whole self. And a sock.", "Sing, O Muse, of {name}, who writes the good code!", "{name}! You! Are! The best! At the typing!", "Heroes ship, {name}. You're a hero. Probably.", "{name}, I'll guard your desk. From everything."],
  shipped: ["{name} SHIPPED IT! Sing, O Muse!", "A homecoming worthy of Odysseus, {name}!"],
  rally: ["BALL. Ball ball ball. BALL.", "Left! Right! Left! I can't take it!"],
  fuss: {
    pat: ["Yes! The head! The good head!", "Thank you, {name}! Thank you thank you!"],
    scratch: ["Ohh, the ear. The leg's going. Can't stop it.", "There! THERE! O, {name}, there!"],
    belly: ["The belly! Achilles never got this!"],
    treat: ["A TREAT! I'd sail to Ithaca for this!", "Nom! {name} is my favourite! Everyone is!"],
  } satisfies Record<Fuss, string[]>,
}

/** the parts of his musings: a bard's frame and a dog's concerns — a fresh epic every time */
export const ARGOS_RIFF = {
  open: ["Sing, O Muse, of", "I have known", "Twenty-four books could not hold", "The gods themselves envy", "Ten years at sea, and still I think of", "Rosy-fingered dawn brings"],
  matter: ["the ball that rolled under the couch.", "the squirrel that got away.", "a sandwich left unguarded.", "the mailman, my nemesis.", "the smell of a new keyboard.", "the great belly rub of yesterday.", "my own tail, which eludes me.", "the sock nobody misses."],
}

/** his bed and his bowl are wherever the room's geometry puts them — these just name the idea */
export function dogBed(bed: Spot): Spot { return bed }
export function dogBowl(bowl: Spot): Spot { return bowl }

/** Argos' line for an occasion: the model's, else his own (`ARGOS`) — `line` is the room's own balloon-text */
export function argos(occasion: keyof typeof ARGOS | `fuss_${Fuss}`, line: (occasion: string, canned: readonly string[], name?: string) => string, name = "") {
  const canned = occasion.startsWith("fuss_") ? ARGOS.fuss[occasion.slice(5) as Fuss] : ARGOS[occasion as Exclude<keyof typeof ARGOS, "fuss">]
  return line(occasion, canned, name)
}

/** you tell Argos where to go — his bed, a turn round the floor, your office — or to sit where he is */
export function dogDo(d: Dog, what: "bed" | "walk" | "office" | "sit", tick: number, ctx: {
  bed(): Spot
  roam(): Spot
  route(x: number, from: number, goal: Spot): Pt[]
  say(text: string): void
  argos(occasion: "bed" | "walk" | "office" | "sit"): string
}) {
  if (what === "sit") { d.path = []; d.mode = "sit"; d.until = tick + 300; d.aisle = d.y; return }
  const spot = (x: number, y: number): Spot => ({ x, y, aisle: y, pose: "stand", face: "left", kind: "roam" })
  const goal = what === "bed" ? ctx.bed() : what === "office" ? spot(60, 140) : ctx.roam()
  d.host = null; d.creep = false
  d.path = [{ x: d.x, y: d.aisle }, ...ctx.route(d.x, d.aisle, goal)]
  d.aisle = goal.aisle; d.mode = "walk"
  ctx.say(ctx.argos(what))
}

/** you send Argos over to someone (`host`, at `goal` beside them): he trots there and cheers them on */
export function dogCheer(d: Dog, host: Actor, goal: Spot, route: (x: number, from: number, goal: Spot) => Pt[]) {
  d.host = keyOf(host.seat); d.cheer = true; d.creep = false
  d.path = [{ x: d.x, y: d.aisle }, ...route(d.x, d.aisle, goal)]
  d.aisle = goal.aisle; d.mode = "walk"
}

/** a click on Argos: a woof and a wag — and if he's not off somewhere, over he rolls for a belly rub */
export function patDog(d: Dog, tick: number, say: (text: string) => void, argos: (occasion: "pat" | "belly") => string) {
  d.woof = tick + 25
  if (d.mode === "sleep") { d.mode = "sit"; d.until = tick + 120 }
  if (!d.path.length) { d.belly = tick + 30; say(argos("belly")) } else say(argos("pat"))
}

/** someone at `by` makes a fuss of Argos */
export function fussDog(d: Dog, by: Actor, tick: number, say: (text: string) => void, argos: (occasion: `fuss_${Fuss}`, name: string) => string) {
  const kind = pick<Fuss>(["pat", "scratch", "belly", "treat"])
  d.fuss = { kind, from: { x: by.x, y: by.y }, until: tick + FUSS }
  if (kind === "belly") d.belly = tick + FUSS
  d.mode = "sit"; d.until = Math.max(d.until, tick + FUSS + 40)
  by.emote = "♥"; by.emoteUntil = tick + FUSS
  say(argos(`fuss_${kind}`, by.seat.agent))
}

/**
 * Argos' day: naps in his bed, drinks, trots the floor, sits by someone at their desk (they get a
 * ♥), drops in on your office, lies in the meeting room. He walks the people's routes, so he keeps
 * off the furniture too.
 */
export function stepDog(d: Dog, ctx: {
  tick: number
  antic: unknown
  quiet(saidUntil: number): boolean
  actors: Map<string, Actor>
  at(kind: string): Actor[]
  bed(): Spot
  bowl(): Spot
  visit(host: Actor): Spot
  roam(): Spot
  route(x: number, from: number, goal: Spot): Pt[]
  table(): { x: number; y: number; w: number; h: number }
  mc: number
  say(text: string): void
  argos(occasion: "visit" | "cheer", name: string): string
  fussDog(by: Actor): void
}): boolean {
  if (d.fuss && ctx.tick >= d.fuss.until) d.fuss = null
  if (ctx.tick < d.belly) return false
  if (d.path.length) {
    if (d.creep && ctx.tick % 3) return false
    const to = d.path[0]!
    d.x += Math.sign(to.x - d.x); d.y += Math.sign(to.y - d.y)
    if (to.x !== d.x) d.face = Math.sign(to.x - d.x)
    if (d.x === to.x && d.y === to.y) d.path.shift()
    if (!d.path.length) {
      const bed = ctx.bed(), asleep = d.x === bed.x && d.y === bed.y
      d.mode = asleep ? "sleep" : "sit"
      d.until = ctx.tick + (asleep ? 900 : 200) + Math.floor(Math.random() * 400)
      const host = d.host ? ctx.actors.get(d.host) : undefined
      if (host && d.cheer) {
        d.cheer = false; host.emote = "♥"; host.emoteUntil = ctx.tick + 60; ctx.say(ctx.argos("cheer", host.seat.agent))
      } else if (host) {
        if (Math.random() < 0.6) ctx.fussDog(host)
        else { host.emote = "♥"; host.emoteUntil = ctx.tick + 40; ctx.say(ctx.argos("visit", host.seat.agent)) }
      }
    }
    return true
  }
  if (ctx.antic) return false
  if (d.mode !== "sleep" && !d.fuss && ctx.quiet(d.saidUntil) && Math.random() < 0.0015) {
    const near = [...ctx.actors.values()].find((a) => !a.moving && !a.path.length && (a.spot.kind === "couch" || a.spot.kind === "cooler" || a.spot.kind === "coffee" || a.spot.kind === "roam") && Math.abs(a.x - d.x) < 22 && Math.abs(a.y - d.y) < 16)
    if (near) { ctx.fussDog(near); return true }
  }
  if (ctx.tick < d.until) return d.mode === "sit" && ctx.tick % 3 === 0
  const r = Math.random(), working = [...ctx.actors.values()].filter((a) => a.spot.kind === "desk" && !a.moving && !a.path.length)
  const host = working.length && r < 0.35 ? pick(working) : null
  const spot = (x: number, y: number, aisle = y): Spot => ({ x, y, aisle, pose: "stand", face: "left", kind: "roam" })
  const t = ctx.table()
  const watch = !host && ctx.at("pingpong").length === 2 && r > 0.85
  const goal: Spot = host ? ctx.visit(host)
    : watch ? { x: t.x + t.w / 2, y: t.y + t.h + 6, aisle: t.y + t.h + 12, pose: "stand", face: "left", kind: "roam" }
    : r < 0.5 ? ctx.bed() : r < 0.6 ? ctx.bowl()
      : r < 0.72 ? spot(40 + Math.floor(Math.random() * 40), 140)
        : r < 0.82 ? spot(ctx.mc - 4, 110, 116)
          : ctx.roam()
  d.host = host ? keyOf(host.seat) : null
  d.path = [{ x: d.x, y: d.aisle }, ...ctx.route(d.x, d.aisle, goal)]
  d.aisle = goal.aisle; d.mode = "walk"
  return true
}

/** Argos, his bed and his bowl */
export function drawDog(sc: Scene, d: Dog, bed: Spot, bowl: Spot, bpm: number | null = null) {
  const f = sc.f
  sc.item(bed.y - 3, () => { sc.px(bed.x - 9, bed.y - 4, 18, 5, tint(ROLE.alarm, ROLE.ground, 0.55)); sc.px(bed.x - 8, bed.y - 3, 16, 3, tint(ROLE.alarm, ROLE.prose, 0.35)) })
  sc.item(bowl.y - 2, () => { sc.px(bowl.x - 3, bowl.y - 2, 6, 2, ROLE.inactive); sc.px(bowl.x - 2, bowl.y - 3, 4, 1, ROLE.key) })
  const belly = sc.tick < d.belly
  const dance = dancing(d.mode, d.fuss, bpm)
  const phase = dance ? Math.floor((sc.tick * bpm!) / 300) % 2 : 0
  const frames = belly ? DOG.belly : DOG[d.mode]
  // walking, his legs; sitting, his tail — wagging double time when he's pleased; asleep, breathing
  const rows0 = frames[belly ? f % 2 : d.mode === "walk" ? Math.floor(sc.tick / 2) % 2 : d.mode === "sit" ? (sc.tick < d.woof ? sc.tick % 2 : Math.floor(f / 2) % 2) : f % 4 < 2 ? 0 : 1]!
  const flipped = dance ? phase === 1 : d.face < 0
  const rows = flipped ? rows0.map((r) => [...r].reverse().join("")) : rows0
  const w = rows[0]!.length, h = rows.length, x = d.x - Math.floor(w / 2), y = d.y - h - (dance ? phase : 0)
  sc.item(d.y, () => {
    const rim = tint(ROLE.prose, ROLE.ground, 0.55), r = { k: rim, e: rim, t: rim, n: rim, i: rim, p: rim, c: rim }
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, -1]] as const) sc.blit(rows, x + dx, y + dy, r)
    sc.blit(rows, x, y, { k: ROLE.body, t: ROLE.body, e: tint(ROLE.body, ROLE.structure, 0.4), n: ROLE.fieldInk, i: ROLE.fieldInk, c: ROLE.fieldInk, p: ROLE.attention })
    if (d.mode === "sleep" && !belly && f % 6 < 3) sc.text("z", x + w + 1, y - 1, ROLE.inactive, 10)
    if (d.creep && f % 4 < 2) sc.text("...", d.x, y - 2, ROLE.inactive, 9)
    if (d.fuss) drawFuss(sc, d.fuss, { x, y, w, h })
    sc.hits.push({ x: x - 1, y: y - 2, w: w + 2, h: h + 3, tip: `${DOG_NAME} - click to pat him`, act: { kind: "dog" } })
  })
  if (d.said && sc.tick >= d.saidFrom && sc.tick < d.saidUntil) sc.balloons.push({ t: "balloon", lines: balloonLines(d.said), cx: d.x, top: y })
}
