// The office's life, room-agnostic: who walks where and when — people to their desks when they
// work (mid-turn), and kept there, leaning back, while their session stays warm; to the lounge
// when it goes cold, into your queue when a thread waits on you, over to whoever they
// consult, up to the board to leave a note — and Nina's day. A room supplies its geometry as a
// `Plan` (its spots, its routes) and draws what the sim says; the sim never draws.
import { asksYou } from "./crew"
import { homeLevel } from "./life"
import { looksGen, overrideFor } from "./looks"
import type { Pets } from "./pets"
import { CAT_NAME, lookOf, type Dir, type Fav, type Look, type Pose } from "./sprites"
import type { Agents, CorkNote, Seat } from "./types"
import { keyMash, nightOwl } from "./eggs"
import { lean, pickDest, speciesBase, type Dest, type Temperament } from "./temperament"
import { bucketFor, NINA, NINA_RIFF, pick, pickFresh, riff, type Fuss } from "./voices"

/** something to do with your idle time, where a room has the thing to do it with */
export type Pastime = "arcade" | "pingpong" | "aquarium" | "window" | "plant" | "chat" | "pet" | "vending" | "foosball" | "pool" | "read"
export type Kind = Fav | Pastime | "desk" | "queue" | "roam" | "exit" | "visit" | "note"
/**
 * A place to be: where to stand, the row you walk along to get there, how you stand once there;
 * `with`, where a partner stands (the far end of the ping-pong table, the other half of a chat) —
 * a spot whose partner is there already draws the next idle person over.
 */
export type Spot = { x: number; y: number; aisle: number; pose: Pose; face: Dir; kind: Kind; with?: Pt }
export type Pt = { x: number; y: number }
export type Actor = {
  seat: Seat; look: Look; lookGen?: number; x: number; y: number; path: Pt[]
  spot: Spot; spotKey: string; pose: Pose; face: Dir; moving: boolean
  until: number; emote: string | null; emoteUntil: number; leaving: boolean
  /** the tick their `doing` last changed (a long one makes them sweat); the tick a just-finished turn's stretch ends */
  doingSince: number; stretch: number
  /** a snack from the machine in hand until `snack`; the tick they last finished a turn; a high-five's hand up until `five`; a coffee with them until `mug` */
  snack: number; finished: number; five: number; mug: number
  /** the tick their last turn ended (or they were first seen between turns), and how warm their session is now: 1 mid-turn or just after, 0 cold */
  cooled: number; warmth: number
}
export type CatMode = "walk" | "sit" | "sleep" | "play" | "zoom"
/**
 * `zoom`: the tick her zoomies end; `leaps`: the room's leaps she is tearing between; `said` what she
 * is saying, from `saidFrom` until `saidUntil`; `stretch`: the tick her wake-up stretch ends; `fuss`: a worker making
 * a fuss of her, from where they are
 */
export type Cat = { name: string; species: "cat" | "rabbit" | "bird"; x: number; y: number; path: Pt[]; mode: CatMode; until: number; face: number; purr: number; byYou: boolean; yarn: number; zoom: number; leaps: Pt[]; said: string | null; saidFrom: number; saidUntil: number; stretch: number; fuss: Fussing | null; errand?: { name: string; kind: "cheer" | "keys" } | null }
/** someone at `from` making a fuss of a pet until `until` */
export type Fussing = { kind: Fuss; from: Pt; until: number }
/** how long a fuss lasts, in ticks; a treat spends the first third in the air */
export const FUSS = 36

/** Nina's places in a room: her nap, your desk, her yarn, her litter, her tower's two perches, the lounge */
export type CatPlan = {
  nap: Pt; desk: Pt; play: Pt; litter: Pt; perches: [Pt, Pt]; lounge: Pt[]; spots: Pt[]
  /** somewhere warm she makes for when it's cold out (a radiator), if the room has one */
  warm?: Pt
  /** the floor below a spot up off it (a desk, a perch, the litter box), or null */
  via(p: Pt): Pt | null
  /** the waypoints between two of her places — a door when they are in different rooms */
  door(from: Pt, to: Pt): Pt[]
  /**
   * The zoomies: per room, the places she tears between — the first a floor spot she lands on when
   * it's over, the rest anything she can leap onto. Straight runs; a room with none has no zoomies.
   */
  leaps: Pt[][]
}
/** a room's geometry, as the sim needs it */
export type Plan<L extends { people: Seat[] }> = {
  layout(a: Agents): L
  /** where someone works, if they have a seat */
  home(l: L, agent: string): Spot | null
  queue: Spot[]
  lounge: Spot[]
  exit: Spot
  pen: Spot
  /** beside whoever is visited */
  visit(host: Actor): Spot
  /** where to stand to drop a suggestion in the box, for a room with one (else they pin it on the board) */
  box?: Spot
  /** somewhere to stroll when the lounge is full */
  roam(l: L): Spot
  /** the waypoints from (x, row `from`) to a goal, kept off the furniture */
  route(x: number, from: number, goal: Spot): Pt[]
  cat: CatPlan
}

// one figure per person, whatever threads they are on
export const keyOf = (r: Seat) => r.agent
export const spotKey = (s: Spot) => `${s.kind}:${s.x}:${s.y}`
const VISIT_MS = 60_000, NOTE_MS = 45_000
/** ticks a finished worker stretches at the desk before leaving it */
export const STRETCH = 20
/** the server's warmth window (`Server.Presence`, an hour by default) in ticks: a warm session's glow fades over it */
export const WARM_TICKS = 36_000
const LOUNGING = new Set<string>(["couch", "cooler", "coffee", "roam", "arcade", "pingpong", "aquarium", "window", "plant", "chat", "pet", "vending", "foosball", "pool", "read"])
/** what someone at a pastime says now and then (over their head): a nap on the couch is a "z" */
const MOODS: Record<string, string[]> = { board: ["?"], cooler: ["~"], coffee: ["♥"], couch: ["z", "*"], arcade: ["!", "*"], pingpong: ["!"], aquarium: ["~", "♥"], window: ["*", "~"], plant: ["♪"], chat: ["~", "?", "!"], pet: ["♥"], vending: ["♪", "?"], foosball: ["!", "*"], pool: ["!", "?"], read: ["…", "?", "♥"] }
/** how the hour pulls at a pastime: coffee in the morning, the machine at lunch, the windows and the couch at night */
export function moment(kind: string, hour: number, weather?: string, party = false) {
  // a birthday: the crowd gathers at the kitchen counter, cake and a drink
  if (party && (kind === "cooler" || kind === "coffee")) return 5
  // the weather out the window pulls first: in for the couch and a book when it pours, out to the glass when it snows
  if (weather === "rain" || weather === "storm") return kind === "couch" || kind === "read" ? 3 : kind === "window" || kind === "arcade" ? 2 : 1
  if (weather === "snow") return kind === "window" ? 4 : kind === "coffee" ? 2 : 1
  if (hour >= 20 || hour < 6) return kind === "window" ? 4 : kind === "couch" || kind === "read" ? 2 : 1
  if (hour >= 7 && hour < 10) return kind === "coffee" ? 4 : 1
  if (hour >= 12 && hour < 14) return kind === "vending" ? 4 : kind === "chat" ? 2 : 1
  return 1
}
/** a thread shipped: confetti over whoever led it, until `until` */
export type Party = { agent: string; until: number }

export class Sim<L extends { people: Seat[] }> {
  protected cat: Cat
  protected temperament: Temperament = { warmth: 0, wits: 0, energy: 0 }
  setTemperament(t: Temperament) { this.temperament = t }
  /** pets.json, resolved: the cat slot's name and temperament */
  setPets(p: Pets) { this.cat.name = p.cat.name; this.cat.species = p.cat.species as Cat["species"]; this.setTemperament(p.cat.temperament) }
  protected actors = new Map<string, Actor>()
  protected tick = 0
  private seeded = false
  private lastGood: Agents | null = null
  /** an actor's current spot on the floor, by agent name — null if they aren't seated here */
  at(agent: string): Spot | null { return this.actors.get(agent)?.spot ?? null }
  /** who you are talking to, by agent name: `text` null while they think, then what they said */
  protected talk = new Map<string, { text: string | null; until: number }>()
  private changed = true
  /** the open threads' leads at the last step: one that is gone has shipped */
  private leads = new Map<number, string>()
  private fived = new Set<string>()
  protected party: Party | null = null
  /** the weather outside, from the snapshot: it pulls at what people do, and Nina wants warm when it's cold */
  protected weather: Agents["weather"] = null
  protected celebrating = false
  /** the office corkboard's notes (`pinboard`), and notes on their way up: an author walks to the board and reads theirs out */
  protected cork: CorkNote[] = []
  private pins = new Map<string, { text: string; until: number; box: boolean }>()
  /** the suggestion box (`suggestionBox`) */
  protected ideas: CorkNote[] = []
  private ideasSeen = false
  private corkSeen = false
  /** what the server's model wrote for each pet, by occasion (`hear`), and the lines already said */
  private voices: Record<string, Record<string, string[]>> = {}
  private spoken = new Set<string>()
  // the last lines said, so a pet doesn't say the same thing twice running
  private recent: string[] = []
  protected discoUntil = 0
  /** the hour it is — a function, so a test can make it the small hours */
  protected hour = () => new Date().getHours()
  /** the warmth window in ticks — a field, so a test can shorten it */
  protected warmTicks = WARM_TICKS

  constructor(protected plan: Plan<L>) {
    this.cat = { name: CAT_NAME, species: "cat", ...plan.cat.nap, path: [], mode: "sleep", until: 300, face: 1, purr: 0, byYou: false, yarn: 0, zoom: 0, leaps: [], said: null, saidFrom: 0, saidUntil: 0, stretch: 0, fuss: null }
  }

  /** a click on Nina: she purrs for a few seconds, and wakes (with a stretch) if she was asleep */
  pet() {
    const c = this.cat
    c.purr = this.tick + 30; c.byYou = false
    if (c.mode === "sleep") { c.mode = "sit"; c.until = this.tick + 150; c.stretch = this.tick + 12 }
    this.catSay(this.line("Nina", "pet", NINA.pet))
  }
  /**
   * The corkboard as the server has it (`GET /api/office/corkboard/:ws`): a note not seen before
   * sends its author up to the board to pin it, reading it out when they get there. The first
   * look is the board as it stands, not a rush of everyone pinning at once.
   */
  pinboard(notes: CorkNote[]) {
    const seen = new Set(this.cork.map((n) => n.id))
    if (this.corkSeen) for (const n of notes) if (!seen.has(n.id)) this.pins.set(n.author, { text: n.body, until: this.tick + 600, box: false })
    this.cork = notes
    this.corkSeen = true
  }
  /** the suggestion box as the server has it: a new one walks its author over to drop it in, reading it out */
  suggestionBox(ideas: CorkNote[]) {
    const seen = new Set(this.ideas.map((n) => n.id))
    if (this.ideasSeen) for (const n of ideas) if (!seen.has(n.id)) this.pins.set(n.author, { text: n.body, until: this.tick + 600, box: true })
    this.ideas = ideas
    this.ideasSeen = true
  }
  /** the pets' lines, fresh from the server (`GET /api/office/pets/:ws`) */
  hear(voices: Record<string, Record<string, string[]>>) { this.voices = voices }
  /**
   * What `pet` says on `occasion`: a line the model wrote that has not been said yet, else (when
   * it wrote none, or every one has been said) one of the `canned` ones — or, given `parts`, now and
   * then one put together from them (`riff`) — never one of the last few said; `{name}` is whoever
   * it is about.
   */
  protected line(pet: string, occasion: string, canned: readonly string[], name = "", parts?: Parameters<typeof riff>[0]) {
    if (pet === "Nina" && canned === (NINA as Record<string, unknown>)[occasion]) canned = bucketFor(occasion, this.temperament, Math.random, this.cat.species)
    const fresh = this.voices[pet]?.[occasion] ?? [], unsaid = fresh.filter((l) => !this.spoken.has(l))
    const l = unsaid.length ? pick(unsaid)
      : parts && Math.random() < 0.5 ? riff(parts)
        : pickFresh(fresh.length && Math.random() < 0.5 ? fresh : canned, this.recent)
    this.spoken.add(l)
    this.recent = [l, ...this.recent].slice(0, 8)
    return l.replaceAll("{name}", name || "you")
  }
  /** Nina says something, over her head for a few seconds — after `delay`, when she is answering someone */
  protected catSay(text: string, ticks = 45, delay = 0) { const c = this.cat; c.said = text; c.saidFrom = this.tick + delay; c.saidUntil = c.saidFrom + ticks; this.changed = true }
  /** a pet that spoke lately keeps quiet a while before speaking up unasked */
  protected quiet(saidUntil: number) { return this.tick > saidUntil + 150 }
  /**
   * Something happened to someone: they started a kind of tool (`what` its kind), finished a turn
   * (`done`), or joined your queue (`queue`). Nina may have an opinion; a room with more pets adds theirs.
   */
  protected noticed(actor: Actor, what: string) {
    const lines = (NINA as Record<string, unknown>)[what]
    const odds = what === "shipped" ? 0.7 : what === "queue" ? 0.4 : what === "done" ? 0.2 : 0.1
    if (Array.isArray(lines) && this.quiet(this.cat.saidUntil) && Math.random() < odds) this.catSay(this.line("Nina", what, lines as string[], actor.seat.agent))
  }
  /** someone was asked something (`text` null) or has answered; an answer shows for ~12 s */
  say(agent: string, text: string | null) { this.talk.set(agent, { text, until: text === null ? Infinity : this.tick + 120 }); this.changed = true }
  /** is anyone settled at a spot of this kind (the TV is on while someone is on the couch) */
  protected using(kind: Kind) { return [...this.actors.values()].some((x) => x.spot.kind === kind && !x.moving) }

  private dest(d: Dest): Pt {
    const p = this.plan.cat
    return d === "nap" ? p.nap : d === "desk" ? p.desk : d === "perch" ? pick(p.perches) : d === "play" ? p.play : d === "litter" ? p.litter : pick(p.spots)
  }

  /** Nina: naps on your rug, sits and flicks her tail, wanders your floor and the lounge */
  private stepCat(): boolean {
    const c = this.cat, p = this.plan.cat
    const at = (q: Pt) => c.x === q.x && c.y === q.y
    if (this.tick < c.stretch) return false
    if (c.fuss && this.tick >= c.fuss.until) { c.fuss = null; return true }
    if (c.mode === "zoom") return this.stepZoomies()
    if (c.path.length) {
      if (this.tick % 2) return false
      const to = c.path[0]!
      c.x += Math.sign(to.x - c.x); c.y += Math.sign(to.y - c.y)
      if (to.x !== c.x) c.face = Math.sign(to.x - c.x)
      if (c.x === to.x && c.y === to.y) c.path.shift()
      if (!c.path.length && c.errand) {
        const { name, kind } = c.errand, host = this.actors.get(name)
        c.errand = null; c.mode = "sit"; c.until = this.tick + (kind === "keys" ? 400 : 200)
        if (host && kind === "cheer") { host.emote = "♥"; host.emoteUntil = this.tick + 60; this.catSay(this.line("Nina", "cheer", NINA.cheer, name), 70) }
        // she sits on their keyboard: whatever they were typing, this is what they type now
        if (host && kind === "keys") { this.say(name, keyMash()); this.catSay(this.line("Nina", "keyboard", NINA.keyboard, name), 70, 20) }
        return true
      }
      if (!c.path.length) {
        const nap = at(p.nap) || (at(p.perches[0]) && Math.random() < 0.7)
        c.mode = nap ? "sleep" : at(p.play) ? "play" : "sit"
        if (at(p.play)) c.face = 1
        c.until = this.tick + (at(p.litter) ? 60 : nap ? 600 : 150) + Math.floor(Math.random() * (at(p.litter) ? 40 : 300))
      }
      return true
    }
    if (c.mode === "play" && this.tick % 3 === 0) { c.yarn = (c.yarn + 1) % 4; return true }
    // nobody leaves her lonely: you pat her when she is on your desk, and anyone idling in the
    // lounge reaches down to her when she is close
    if (this.tick >= c.purr) {
      if (at(p.desk) && Math.random() < 0.02 * lean(this.temperament.warmth)) { c.purr = this.tick + 30; c.byYou = true; return true }
      // a fuss is an occasion, not a fixture: one at a time, and not while she still has the last to say
      if (c.mode !== "sleep" && !c.path.length && this.quiet(c.saidUntil)) for (const a of this.actors.values()) {
        if (a.moving || a.path.length || !LOUNGING.has(a.spot.kind) || Math.abs(a.x - c.x) > 18 || Math.abs(a.y - c.y) > 16 || Math.random() > 0.0015 * lean(this.temperament.energy)) continue
        // a snack from the machine goes to her, whatever else they had in mind
        const kind = a.snack > this.tick ? "treat" : pick<Fuss>(["pat", "pat", "scratch", "treat"])
        if (kind === "treat") a.snack = 0
        c.fuss = { kind, from: { x: a.x, y: a.y }, until: this.tick + FUSS }; c.mode = "sit"; c.until = this.tick + FUSS + 60
        c.purr = this.tick + FUSS; c.byYou = false; a.emote = "♥"; a.emoteUntil = this.tick + FUSS
        this.catSay(this.line("Nina", `fuss_${kind}`, NINA.fuss[kind], a.seat.agent))
        return true
      }
    }
    if (this.tick < c.until || this.tick < c.purr) return false
    const company = [...this.actors.values()].some((a) => !a.moving && LOUNGING.has(a.spot.kind))
    const r = Math.random()
    // now and then she goes to sit on the keyboard of someone hard at work
    const typing = [...this.actors.values()].filter((a) => a.spot.kind === "desk" && !a.moving && a.seat.thinking)
    if (typing.length && r > 0.97 && c.mode !== "sleep") return this.catKeyboard(pick(typing).seat.agent)
    // the small hours give her ideas
    const leaps = r < (nightOwl(this.hour()) ? 0.15 : 0.05) * lean(this.temperament.energy) && c.mode !== "sleep" && !p.via(c) ? this.leapsHere() : null
    if (leaps) { c.mode = "zoom"; c.leaps = leaps; c.zoom = this.tick + 70 + Math.floor(Math.random() * 60); return true }
    const cold = (this.weather?.temp_c ?? 20) < 10
    const to = cold && p.warm && r < 0.35 ? p.warm
      : company && r < 0.3 ? pick(p.lounge)
      : this.dest(pickDest(this.temperament, r, speciesBase(c.species)))
    const down = p.via(c), up = p.via(to)
    c.path = [...(down ? [down] : []), ...p.door(down ?? c, up ?? to), ...(up ? [up] : []), { ...to }]; c.mode = "walk"
    return true
  }

  /**
   * You tell Nina what to do (she is a cat: she does it, then her own day carries on): nap on her
   * rug, play with the yarn, come to your desk, or the zoomies where she is (or, with no leaps
   * near, round your office). False when there is nothing to do it with.
   */
  catDo(what: "nap" | "play" | "come" | "zoomies"): boolean {
    const c = this.cat, p = this.plan.cat
    if (what === "zoomies") {
      const leaps = this.leapsHere() ?? p.leaps[0]
      if (!leaps?.length) return false
      c.path = []; c.mode = "zoom"; c.leaps = leaps; c.zoom = this.tick + 90
    } else {
      const to = what === "nap" ? p.nap : what === "play" ? p.play : p.desk
      const down = c.mode === "zoom" ? null : p.via(c), up = p.via(to)
      c.path = [...(down ? [down] : []), ...p.door(down ?? c, up ?? to), ...(up ? [up] : []), { ...to }]; c.mode = "walk"
    }
    c.until = this.tick + 150; this.catSay(this.line("Nina", what, NINA[what]))
    return true
  }

  /**
   * You send Nina over to someone (their name): she walks to them and, when she gets there, tells
   * them something encouraging, in her way — and they get a ♥. False when they aren't in the room.
   */
  catCheer(name: string): boolean { return this.catErrand(name, "cheer") }

  /** Nina goes and sits on someone's keyboard (their name); false when they aren't in the room */
  catKeyboard(name: string): boolean { return this.catErrand(name, "keys") }

  private catErrand(name: string, kind: "cheer" | "keys"): boolean {
    const host = this.actors.get(name)
    if (!host) return false
    const c = this.cat, p = this.plan.cat, to = this.plan.visit(host)
    const down = c.mode === "zoom" ? null : p.via(c)
    c.path = [...(down ? [down] : []), ...p.door(down ?? c, to), { ...to }]
    c.mode = "walk"; c.until = this.tick + 150; c.errand = { name, kind }
    return true
  }

  /** the Konami code: a heart for everyone, confetti over them all, and a beat for the pets to dance to */
  disco() {
    this.discoUntil = this.tick + 300
    for (const x of this.actors.values()) { x.emote = "♥"; x.emoteUntil = this.tick + 120 }
    this.changed = true
  }

  /** the home level on the last snapshot; null until one has one, so a start-up is only a baseline */
  private levelSeen: number | null = null
  /** a level-up in the snapshot: the same party as the Konami code; rooms add to it */
  protected levelUp(_level: number) { this.disco() }

  /** the beat the room dances to now: a disco's, else none (a room with music says otherwise) */
  bpm(): number | null { return this.tick < this.discoUntil ? 140 : null }

  /** the leaps of the room she is in (the group with a spot nearest her), if it has any near */
  private leapsHere(): Pt[] | null {
    const c = this.cat, d = (q: Pt) => Math.abs(q.x - c.x) + Math.abs(q.y - c.y)
    let best: Pt[] | null = null, bestD = 90
    for (const g of this.plan.cat.leaps) for (const q of g) if (d(q) < bestD) { best = g; bestD = d(q) }
    return best
  }
  /** the zoomies: two pixels a tick, from leap to leap, until it's over and she lands and sits like nothing happened */
  private stepZoomies(): boolean {
    const c = this.cat, g = c.leaps
    if (!c.path.length) {
      if (this.tick >= c.zoom) {
        if (c.x === g[0]!.x && c.y === g[0]!.y) { c.mode = "sit"; c.until = this.tick + 200; c.purr = this.tick + 30; c.byYou = false; return true }
        c.path = [{ ...g[0]! }]
      } else {
        const next = g.filter((q) => q.x !== c.x || q.y !== c.y)
        c.path = [{ ...next[Math.floor(Math.random() * next.length)]! }]
      }
    }
    for (let i = 0; i < 2 && c.path.length; i++) {
      const to = c.path[0]!
      c.x += Math.sign(to.x - c.x); c.y += Math.sign(to.y - c.y)
      if (to.x !== c.x) c.face = Math.sign(to.x - c.x)
      if (c.x === to.x && c.y === to.y) c.path.shift()
    }
    return true
  }

  /**
   * Advance one tick (100 ms): retarget everyone from the roster, then walk. True when the room
   * looks different — someone moved, or the 400 ms animation frame turned — so the surface redraws
   * only then.
   */
  step(a: Agents): boolean {
    // the channel down (a server restart) is a pause: the room carries on from the last good look
    if (a.ok) this.lastGood = a
    else if (this.lastGood) a = { ...this.lastGood, ok: false, note: a.note }
    this.tick++
    const level = homeLevel(a)
    if (level !== null && this.levelSeen !== null && level > this.levelSeen) this.levelUp(level)
    this.levelSeen = level
    this.weather = a.weather ?? this.weather
    this.celebrating = (a.celebrations ?? []).length > 0
    let changed = this.changed || this.tick % 4 === 0
    this.changed = false
    for (const [k, v] of this.talk) if (this.tick > v.until) { this.talk.delete(k); changed = true }
    const asleep = this.cat.mode === "sleep"
    if (this.stepCat()) changed = true
    // the night owls: in the small hours, someone at their desk yawns now and then
    if (nightOwl(this.hour())) for (const x of this.actors.values()) {
      if (x.spot.kind === "desk" && !x.moving && this.tick >= x.emoteUntil && Math.random() < 1 / 900) { x.emote = "z"; x.emoteUntil = this.tick + 45; changed = true }
    }
    if (asleep && this.cat.mode !== "sleep" && this.cat.mode !== "zoom") {
      this.cat.stretch = this.tick + 12
      if (Math.random() < 0.5) this.catSay(this.line("Nina", "wake", NINA.wake))
    }
    if (this.cat.mode !== "sleep" && this.quiet(this.cat.saidUntil) && Math.random() < 1 / 1500) this.catSay(this.line("Nina", "muse", NINA.muse, "", NINA_RIFF))
    const plan = this.plan, l = plan.layout(a)
    const threadOf = (id: number) => a.threads.find((t) => t.id === id)
    const asks = l.people.filter((p) => asksYou(p.agent, threadOf(p.thread_id))).sort((p, q) => p.thread_id - q.thread_id)
    // a thread gone from the open ones has shipped — unless many went at once (a new view, the channel down)
    const leads = new Map(a.threads.filter((t) => t.lead).map((t) => [t.id, t.lead!]))
    const gone = [...this.leads].filter(([id]) => !leads.has(id))
    if (a.ok && gone.length && gone.length <= 2) for (const [, who] of gone) { const x = this.find(who); if (x) this.ship(x) }
    if (a.ok) this.leads = leads
    if (this.party && this.tick > this.party.until) this.party = null
    for (const [who, pin] of this.pins) if (this.tick > pin.until) this.pins.delete(who)
    const live = new Set(l.people.map(keyOf))
    for (const r of l.people) {
      const k = keyOf(r)
      const actor = this.actors.get(k)
      if (actor) {
        if ((r.doing ?? null) !== (actor.seat.doing ?? null)) { actor.doingSince = this.tick; if (r.doing) this.noticed(actor, r.doing) }
        // a turn just ended at the desk: a good stretch before getting up
        if (actor.seat.thinking && !r.thinking && actor.spot.kind === "desk" && !actor.moving) { actor.stretch = this.tick + STRETCH; actor.finished = this.tick; this.noticed(actor, "done") }
        if (actor.seat.thinking && !r.thinking) actor.cooled = this.tick
        if (actor.lookGen !== looksGen()) { actor.look = { ...lookOf(r.agent), ...overrideFor(r.agent) }; actor.lookGen = looksGen() } // undefined !== 0 on a fixture built without it: fine, it just computes once
        actor.seat = r; actor.leaving = false; continue
      }
      const at = this.seeded ? plan.exit : plan.home(l, r.agent) ?? plan.lounge[this.actors.size % plan.lounge.length]!
      this.actors.set(k, { seat: r, look: { ...lookOf(r.agent), ...overrideFor(r.agent) }, lookGen: looksGen(), x: at.x, y: at.y, path: [], spot: at, spotKey: this.seeded ? "" : spotKey(at), pose: at.pose, face: at.face, moving: false, until: 0, emote: null, emoteUntil: 0, leaving: false, doingSince: this.tick, stretch: 0, snack: 0, finished: -1000, five: 0, mug: 0, cooled: this.tick, warmth: r.thinking ? 1 : r.warmth ?? (r.warm ? 1 : 0) })
    }
    if (a.ok) this.seeded = true
    // a wave on the way in (whoever walks in from the exit) and on the way out
    for (const [k, actor] of this.actors) {
      if (!live.has(k) && !actor.leaving) { actor.leaving = true; actor.emote = "~"; actor.emoteUntil = this.tick + 30 }
      else if (this.seeded && actor.spotKey === "" && !actor.emote) { actor.emote = "~"; actor.emoteUntil = this.tick + 30 }
    }

    // a consult walks the asker over to whoever they asked; a note walks its author to the board
    const now = Date.now()
    const visiting = new Map(a.visits.filter((v) => now - Date.parse(v.at) < VISIT_MS).map((v) => [v.from, v.to]))
    const writing = new Set(a.notes.filter((n) => now - Date.parse(n.at) < NOTE_MS).map((n) => n.author))
    let host: Actor | undefined
    const held = new Set([...this.actors.values()].map((x) => x.spotKey))
    for (const [k, actor] of this.actors) {
      const slot = asks.findIndex((r) => keyOf(r) === k)
      const home = plan.home(l, actor.seat.agent)
      actor.warmth = actor.seat.thinking ? 1 : actor.seat.warmth ?? (actor.seat.warm ? Math.max(0, 1 - (this.tick - actor.cooled) / this.warmTicks) : 0)
      let goal: Spot
      if (actor.leaving) goal = plan.exit
      else if (slot >= 0) goal = plan.queue[Math.min(slot, plan.queue.length - 1)]!
      else if (visiting.has(actor.seat.agent) && (host = this.find(visiting.get(actor.seat.agent)!))) goal = plan.visit(host)
      else if (writing.has(actor.seat.agent) || this.pins.has(actor.seat.agent)) goal = this.pins.get(actor.seat.agent)?.box && plan.box ? plan.box : plan.pen
      else if ((actor.seat.thinking || this.tick < actor.stretch) && home) goal = home
      else if (actor.seat.warm && home) goal = home
      else goal = this.idleGoal(actor, held, l)
      const gk = spotKey(goal)
      if (gk !== actor.spotKey) {
        held.delete(actor.spotKey); held.add(gk)
        // settled somewhere, they leave the way they came: back to its aisle first, never through what is in front of them
        const from = actor.path.length === 0 ? actor.spot.aisle : actor.y
        actor.path = plan.route(actor.x, from, goal)
        actor.spot = goal; actor.spotKey = gk; actor.pose = "stand"
        if (goal.kind === "queue") this.noticed(actor, "queue")
        // a pastime holds them a minute or two before the next
        actor.until = this.tick + 400 + Math.floor(Math.random() * 800)
      }
      // someone you are talking to stops where they are and faces you until they have answered
      if (this.talk.get(actor.seat.agent)?.text === null) { actor.moving = false; if (actor.pose === "stand") actor.face = "down" }
      else this.walk(actor, goal.kind === "desk" || goal.kind === "queue" || !actor.look.slow ? 2 : 1)
      if (actor.moving) changed = true
      else if (goal.kind === "visit" || goal.kind === "note") {
        // arrived: the two of them talk, or the pen moves
        const e = goal.kind === "note" ? "✎" : "~"
        // a corkboard note: pinned, and read out
        const pin = goal.kind === "note" ? this.pins.get(actor.seat.agent) : undefined
        if (pin) { this.pins.delete(actor.seat.agent); this.say(actor.seat.agent, pin.text) }
        if (actor.emote !== e) { actor.emote = e; changed = true }
        actor.emoteUntil = this.tick + 5
        const h = goal.kind === "visit" ? this.find(visiting.get(actor.seat.agent)!) : undefined
        if (h && h.emote !== "~") { h.emote = "~"; h.emoteUntil = this.tick + 5; changed = true }
      }
      if (actor.leaving && !actor.moving && actor.path.length === 0) { this.actors.delete(k); changed = true; continue }
      // at the machine: a snack drops, and it goes where they go next
      if (!actor.moving && !actor.path.length && actor.spot.kind === "vending" && actor.snack < this.tick && Math.random() < 0.03) { actor.snack = this.tick + 900; changed = true }
      // a coffee poured goes back to the desk with them, and steams there a while
      if (!actor.moving && !actor.path.length && actor.spot.kind === "coffee" && actor.mug < this.tick && Math.random() < 0.03) { actor.mug = this.tick + 3000; changed = true }
      if (actor.emote && this.tick > actor.emoteUntil) { actor.emote = null; changed = true }
      if (!actor.emote && !actor.moving && Math.random() < 0.006) {
        const moods = MOODS[actor.spot.kind]
        actor.emote = moods ? moods[Math.floor(Math.random() * moods.length)]! : actor.look.emote
        actor.emoteUntil = this.tick + 25
        changed = true
      }
    }
    if (this.highFives()) changed = true
    return changed
  }

  /** a thread `actor` led has shipped: confetti, a cheer from everyone idle, and the pets' opinions */
  protected ship(actor: Actor) {
    this.party = { agent: actor.seat.agent, until: this.tick + 60 }
    actor.emote = "!"; actor.emoteUntil = this.tick + 40
    for (const x of this.actors.values()) if (x !== actor && !x.moving && LOUNGING.has(x.spot.kind)) { x.emote = "*"; x.emoteUntil = this.tick + 30 }
    this.noticed(actor, "shipped")
    this.changed = true
  }

  /** someone who just finished a turn high-fives whoever they pass, once each */
  private highFives(): boolean {
    let any = false
    const all = [...this.actors.values()]
    for (const a of all) {
      if (this.tick - a.finished > 400) continue
      for (const b of all) {
        if (a === b || Math.abs(a.x - b.x) > 10 || Math.abs(a.y - b.y) > 4 || a.pose !== "stand" || b.pose !== "stand") continue
        const key = `${a.seat.agent}|${b.seat.agent}|${a.finished}`
        if (this.fived.has(key)) continue
        if (this.fived.size > 200) this.fived.clear()
        this.fived.add(key)
        a.five = b.five = this.tick + 12
        a.emote = b.emote = "*"; a.emoteUntil = b.emoteUntil = this.tick + 15
        any = true
      }
    }
    return any
  }

  /** where someone is now, by name — at their desk before anywhere else */
  private find(agent: string): Actor | undefined {
    const all = [...this.actors.values()].filter((x) => x.seat.agent === agent && !x.leaving)
    return all.find((x) => x.spot.kind === "desk") ?? all[0]
  }

  private idleGoal(actor: Actor, held: Set<string>, l: L): Spot {
    const cur = actor.spot
    const idle = cur.kind === "board" || LOUNGING.has(cur.kind)
    if (idle && this.tick < actor.until) return cur
    const free = this.plan.lounge.filter((s) => !held.has(spotKey(s)) && spotKey(s) !== actor.spotKey)
    // someone waiting at the far end of the table, or half a chat: go and make it a pair
    const waiting = free.filter((s) => s.with && held.has(spotKey({ ...s, ...s.with })))
    if (waiting.length && Math.random() < 0.7) return waiting[Math.floor(Math.random() * waiting.length)]!
    // their favourite pulls three times as hard, and the hour has its say
    const hour = this.hour(), weight = (s: Spot) => (s.kind === actor.look.fav ? 3 : 1) * moment(s.kind, hour, this.weather?.kind, this.celebrating)
    let roll = Math.random() * free.reduce((n, s) => n + weight(s), 0)
    return free.find((s) => (roll -= weight(s)) < 0) ?? this.plan.roam(l)
  }

  private walk(actor: Actor, speed: number) {
    actor.moving = false
    let budget = speed
    while (budget > 0 && actor.path.length) {
      const p = actor.path[0]!
      const dx = p.x - actor.x, dy = p.y - actor.y
      if (dx === 0 && dy === 0) { actor.path.shift(); continue }
      actor.moving = true
      if (dx !== 0) { const s = Math.sign(dx) * Math.min(budget, Math.abs(dx)); actor.x += s; budget -= Math.abs(s); actor.face = dx < 0 ? "left" : "right" }
      else { const s = Math.sign(dy) * Math.min(budget, Math.abs(dy)); actor.y += s; budget -= Math.abs(s); actor.face = dy < 0 ? "up" : "down" }
    }
    if (!actor.path.length) { actor.pose = actor.spot.pose; if (!actor.moving) actor.face = actor.spot.face }
  }
}
