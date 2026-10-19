import { expect, test } from "bun:test"
import { CARD_PARTS, HELPERS, KEYS, POLYSEMY, SHADOWS, type Binding, type Scope, type Shadow } from "../tui/keys"
import { PLAY, playable } from "../tui/sandbox"

// A card's own actions run before the global keys, and in the sandbox the play keys run before
// both: a key that means two things on one screen is a key that lies — `q` that doesn't quit, a
// listed key that fires a toy instead. The table in tui/keys.ts is the only place a key is
// written down, so it is the only thing read here; every collision must be declared in it.
const all: readonly Binding[] = KEYS
const keysOf = (b: Binding) => b.key.split(" ")
const sameMeaning = (a: Binding, b: Binding) => a.label.startsWith(b.label) || b.label.startsWith(a.label)
const inScope = (pattern: Scope, s: Scope) => pattern === s || (pattern === "card:*" && s.startsWith("card:"))

/** the scopes live together on a screen: a card (its own, its helpers'), the globals, and the play keys in the sandbox */
const screens = [...new Set(all.map((b) => b.scope))]
  .filter((s) => (s.startsWith("card:") && !HELPERS.includes(s)) || s === "reader")
  .map((s) => ({ screen: s, scopes: [s, ...(CARD_PARTS[s] ?? []), "global", "sandbox-play"] as Scope[] }))

const clashes = () => {
  const found = new Map<string, { key: string; a: Scope; b: Scope; ids: string[] }>()
  for (const { screen, scopes } of screens) {
    const live = all.filter((b) => scopes.includes(b.scope))
    for (const [i, x] of live.entries()) for (const y of live.slice(i + 1)) {
      if (x.scope === y.scope && x.mode && y.mode && x.mode !== y.mode) continue
      if (sameMeaning(x, y)) continue
      for (const k of keysOf(x).filter((k) => k !== "esc" && keysOf(y).includes(k))) {
        const [a, b] = [x.scope, y.scope].sort() as [Scope, Scope]
        const id = `${k} ${a} ${b}`
        const f = found.get(id) ?? { key: k, a, b, ids: [] }
        f.ids.push(`${screen}: ${x.id} / ${y.id}`)
        found.set(id, f)
      }
    }
  }
  return [...found.values()]
}
const covers = (s: Shadow, c: { key: string; a: Scope; b: Scope }) =>
  s.key === c.key && ([[c.a, c.b], [c.b, c.a]] as const).some(([w, o]) => inScope(s.winner, w) && s.over.some((p) => inScope(p, o)))

test("the table reads: ids are unique, every key has a label, and the scopes the screens need exist", () => {
  expect(new Set(all.map((b) => b.id)).size).toBe(all.length)
  expect(all.filter((b) => !b.key || !b.label)).toEqual([])
  expect(all.filter((b) => b.scope === "global").flatMap(keysOf)).toEqual(expect.arrayContaining(["/", "q", "esc", "?"]))
  expect(screens.map((s) => s.screen)).toEqual(expect.arrayContaining(["card:home", "card:life", "card:person", "card:hall", "card:help", "reader"]))
})

test("every collision on a screen is declared in the table", () => {
  const undeclared = clashes().filter((c) => !SHADOWS.some((s) => covers(s, c))).map((c) => `${c.key}: ${c.a} vs ${c.b} (${c.ids[0]})`)
  expect(undeclared).toEqual([])
})

test("every declared collision still happens (a stale exception hides the next real one)", () => {
  const live = clashes()
  const stale = SHADOWS.filter((s) => !live.some((c) => covers(s, c)))
  expect(stale.map((s) => `${s.key} ${s.winner} over ${s.over.join(" ")}`)).toEqual([])
})

test("a key with several meanings across cards lists every one of them", () => {
  for (const p of POLYSEMY) {
    const bound = all.filter((b) => keysOf(b).includes(p.key)).map((b) => b.id)
    expect([...p.ids as readonly string[]].sort()).toEqual(bound.sort())
    expect(new Set(all.filter((b) => (p.ids as readonly string[]).includes(b.id)).map((b) => b.label)).size).toBeGreaterThan(1)
  }
})

test("in the sandbox no card shows a key the play keys shadow, and the pane draws through that filter", async () => {
  const play = new Set(PLAY.map((p) => p.key))
  for (const { screen, scopes } of screens) {
    const acts = all.filter((b) => scopes.includes(b.scope) && b.scope !== "global" && b.scope !== "sandbox-play" && b.scope !== "reader").map((b) => ({ key: b.key }))
    expect(playable(acts).filter((x) => play.has(x.key)), screen).toEqual([])
  }
  expect(all.some((b) => b.scope === "card:home" && play.has(b.key))).toBe(true)
  const src = await Bun.file(new URL("../tui/main.ts", import.meta.url)).text()
  expect(src.slice(src.indexOf("function drawPane(")).includes("playable(")).toBe(true)
})

test("no play key is a hinted global", () => {
  const hinted = all.filter((b) => b.scope === "global" && !b.quiet).flatMap(keysOf)
  expect(PLAY.filter((p) => hinted.includes(p.key))).toEqual([])
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
