import { expect, test } from "bun:test"
import { PLAY, playable } from "../tui/sandbox"

// A card's own actions run before the global keys, and in the sandbox the play keys run before
// both: a card key that collides is a key that lies — `q` that doesn't quit, a listed key that
// fires a toy instead. main.ts can't be imported (it is the app), so its cards are read as source.
const src = await Bun.file(new URL("../tui/main.ts", import.meta.url)).text()
const bodyOf = (head: string) => {
  const at = src.indexOf(head)
  expect(at).toBeGreaterThan(-1)
  return src.slice(at, src.indexOf("\n}\n", at))
}
const keysIn = (s: string) => [...s.matchAll(/key: "([^"]+)", label: (?:"([^"]*)"|`([^`]*)`)?/g)].map((m) => ({ key: m[1]!, label: m[2] ?? m[3] ?? "" }))
const globals = keysIn(src.slice(src.indexOf("const GLOBALS"), src.indexOf("\n", src.indexOf("const GLOBALS"))))
  .flatMap((h) => h.key.split(" ").map((key) => ({ key, label: h.label })))
const helpers = [...src.matchAll(/^function (\w+Actions)\(/gm)].map((m) => m[1]!)
const cards = bodyOf("function detail(").split(/\n {4}case "/).slice(1).map((block) => {
  const kind = block.slice(0, block.indexOf('"'))
  const own = [...keysIn(block), ...helpers.filter((h) => block.includes(`${h}(`)).flatMap((h) => keysIn(bodyOf(`function ${h}(`)))]
  return { kind, keys: own }
})

test("the source reads: globals, and every card the pane shows", () => {
  expect(globals.map((g) => g.key)).toEqual(expect.arrayContaining(["/", "q", "esc"]))
  expect(cards.map((c) => c.kind)).toEqual(expect.arrayContaining(["home", "life", "person", "hall"]))
})

test("no card's action takes a global key for something else (esc is every card's way back)", () => {
  const clash = cards.flatMap((c) => c.keys
    .filter((x) => x.key !== "esc")
    .flatMap((x) => globals.filter((g) => g.key === x.key && !x.label.startsWith(g.label)).map((g) => `${c.kind}: ${x.key} "${x.label}" shadows "${g.label}"`)))
  expect(clash).toEqual([])
})

test("in the sandbox no card shows a key the play keys shadow, and the pane draws through that filter", () => {
  const play = new Set(PLAY.map((p) => p.key))
  for (const c of cards) expect(playable(c.keys).filter((x) => play.has(x.key))).toEqual([])
  expect(cards.find((c) => c.kind === "home")!.keys.some((x) => play.has(x.key))).toBe(true)
  expect(bodyOf("function drawPane(").includes("playable(")).toBe(true)
})

test("no play key is a global", () => {
  expect(PLAY.filter((p) => globals.some((g) => g.key === p.key))).toEqual([])
})
