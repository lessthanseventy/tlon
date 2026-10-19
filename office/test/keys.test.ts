import { expect, test } from "bun:test"
import { CARD_PARTS, HELPERS, KEYS, OMITS, verbOf, type Binding, type Scope } from "../tui/keys"
import { balloonLines } from "../kit/canvas"
import { PLAY } from "../tui/sandbox"

// A key means one thing everywhere. A card's own actions run before the global keys, and in the
// sandbox the play keys run before both: a key that meant two things would be a key that lies —
// `q` that doesn't quit, a listed key that fires a toy instead. The table in tui/keys.ts is the only
// place a key is written down, so it is the only thing read here.
const all: readonly Binding[] = KEYS
/** the one exemption from "a key has one verb": the look editor is a paint mode that takes every key before any card does (its letters paint, `m` mirrors), so it shares letters with the card keys it hides */
const PAINT_MODES: readonly Scope[] = ["card:look-editor"]
const keysOf = (b: Binding) => b.key.split(" ")
/** letters, symbols and esc carry one verb; digits are a card's own numbered menu, ⏎ and space and the arrows are the lit row */
const guarded = (k: string) => k === "esc" || (k.length === 1 && !/\d/.test(k))

/** the scopes live together on a screen: a card (its own, its helpers'), the globals, and the play keys in the sandbox */
const screens = [...new Set(all.map((b) => b.scope))]
  .filter((s) => (s.startsWith("card:") && !HELPERS.includes(s)) || s === "reader")
  .map((s) => ({ screen: s, scopes: [s, ...(CARD_PARTS[s] ?? []), "global", "sandbox-play"] as Scope[] }))

test("the table reads: ids are unique, every key has a label, and the scopes the screens need exist", () => {
  expect(new Set(all.map((b) => b.id)).size).toBe(all.length)
  expect(all.filter((b) => !b.key || !b.label)).toEqual([])
  expect(all.filter((b) => b.scope === "global").flatMap(keysOf)).toEqual(expect.arrayContaining(["/", "q", "esc", "?"]))
  expect(screens.map((s) => s.screen)).toEqual(expect.arrayContaining(["card:home", "card:life", "card:person", "card:hall", "card:help", "reader"]))
})

test("no key has two verbs: one meaning per key, everywhere", () => {
  const verbs = new Map<string, Map<string, string[]>>()
  for (const b of all.filter((b) => !PAINT_MODES.includes(b.scope))) for (const k of keysOf(b).filter(guarded)) {
    const byVerb = verbs.get(k) ?? new Map<string, string[]>()
    byVerb.set(verbOf(b), [...(byVerb.get(verbOf(b)) ?? []), b.id])
    verbs.set(k, byVerb)
  }
  const clashes = [...verbs].filter(([, v]) => v.size > 1).map(([k, v]) => `${k}: ${[...v].map(([verb, ids]) => `${verb} (${ids.join(", ")})`).join(" vs ")}`)
  expect(clashes).toEqual([])
})

test("a screen binds a key once: a second row on the same key is a mode apart or the global one", () => {
  const twice: string[] = []
  for (const { screen, scopes } of screens) {
    const live = all.filter((b) => scopes.includes(b.scope) && !(OMITS[screen] as readonly string[] | undefined)?.includes(b.id))
    for (const [i, x] of live.entries()) for (const y of live.slice(i + 1)) {
      if (x.mode && y.mode && x.scope === y.scope && x.mode !== y.mode) continue
      if (x.scope === "global" || y.scope === "global") continue
      for (const k of keysOf(x).filter((k) => guarded(k) && keysOf(y).includes(k))) twice.push(`${screen}: ${k} ${x.id} / ${y.id}`)
    }
  }
  expect([...new Set(twice)]).toEqual([])
})

test("a card binds a digit once: the pet cards' numbered menus are per species, never twice on one card", () => {
  const twice: string[] = []
  for (const { screen, scopes } of screens) {
    const live = all.filter((b) => scopes.includes(b.scope) && !PAINT_MODES.includes(b.scope))
    for (const [i, x] of live.entries()) for (const y of live.slice(i + 1)) {
      if (x.scope === y.scope && x.mode !== y.mode) continue
      for (const k of keysOf(x).filter((k) => /^\d$/.test(k) && keysOf(y).includes(k))) twice.push(`${screen}: ${k} ${x.id} / ${y.id}`)
    }
  }
  expect(twice).toEqual([])
  expect(all.filter((b) => b.scope === "card:pet" && /^\d$/.test(b.key)).every((b) => b.mode)).toBe(true)
})

test("the look editor's keys are in the table, and its hint line is drawn from it", async () => {
  expect(all.filter((b) => b.scope === "card:look-editor").map((b) => b.id)).toEqual(expect.arrayContaining(["lookedit.mirror", "lookedit.view", "lookedit.paint"]))
  expect(all.find((b) => b.id === "lookedit.mirror")?.key).toBe("m")
  const src = await Bun.file(new URL("../tui/main.ts", import.meta.url)).text()
  expect(src).not.toContain("1/2/3 view")
})

test("the play keys are shifted letters, and nothing else answers to one", () => {
  expect(PLAY.length).toBeGreaterThan(0)
  expect(PLAY.every((p) => /^[A-Z]$/.test(p.key))).toBe(true)
  const play = new Set(PLAY.map((p) => p.key))
  expect(all.filter((b) => b.scope !== "sandbox-play" && keysOf(b).some((k) => play.has(k))).map((b) => b.id)).toEqual([])
})

test("no play key is a hinted global", () => {
  const hinted = all.filter((b) => b.scope === "global" && !b.quiet).flatMap(keysOf)
  expect(PLAY.filter((p) => hinted.includes(p.key))).toEqual([])
})

test("every global hint's key is bound, and the crew hint names the key that opens the crew", () => {
  expect(all.find((b) => b.id === "global.crew")?.key).toBe("c")
  expect(all.find((b) => b.id === "home.c")?.key).toBe("c")
})

test("the table is the only source: no key is spelled out as a literal outside tui/keys.ts", async () => {
  for (const f of ["main.ts", "reader.ts", "sandbox.ts", "talk.ts", "pane.ts", "hall.ts", "store.ts"]) {
    const src = await Bun.file(new URL(`../tui/${f}`, import.meta.url)).text()
    expect(src.match(/key: "/g) ?? [], f).toEqual([])
  }
})

test("? is the help key everywhere: a global, and the help card lists the reader's keys it handles", async () => {
  expect(all.find((b) => b.scope === "global" && b.key === "?")?.label).toBe("help")
  expect(all.some((b) => b.scope === "card:help")).toBe(true)
  const { READER_KEYS } = await import("../tui/reader")
  const reader = await Bun.file(new URL("../tui/reader.ts", import.meta.url)).text()
  const body = reader.slice(reader.indexOf("  key(k: string"), reader.indexOf("  paste("))
  for (const h of READER_KEYS) for (const k of h.key.split(" ")) expect(body).toContain(`case "${k}"`)
})

test("the screen is the room: no hint says ctrl+] goes to the lobby", async () => {
  expect(all.find((b) => b.id === "global.room")?.label).toBe("room")
  for (const f of ["main.ts", "reader.ts", "keys.ts"]) expect(await Bun.file(new URL(`../tui/${f}`, import.meta.url)).text(), f).not.toMatch(/ctrl\+\] lobby/)
})

test("a clipped balloon names the key that opens the conversation", () => {
  expect(all.find((b) => b.id === "person.v")?.key).toBe("v")
  expect(balloonLines("word ".repeat(60))[3]).toMatch(/\(v\)$/)
})
