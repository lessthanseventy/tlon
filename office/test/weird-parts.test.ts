// The weird end of the catalogue: ticket #98's parts exist, in the slot a figure wears them in.
import { expect, test } from "bun:test"
import { gearOf, PARTS } from "../kit/parts"

const WEIRD = { duck: "head", fishbowl: "head", cone: "head", stormcloud: "head", halo: "head", plantpot: "head", ufo: "head", snail: "neck", bananaphone: "hand", partyhorn: "hand" } as const

test("each weird part is in the library, in its slot, and draws every view", () => {
  for (const [id, slot] of Object.entries(WEIRD)) {
    expect({ id, slot: PARTS[id]?.slot }).toEqual({ id, slot })
    const g = gearOf({ id })!
    for (const view of ["front", "side", "back"] as const) expect({ id, view, drawn: Object.keys(g[view]).length > 0 }).toEqual({ id, view, drawn: true })
  }
})

test("the duck is a yellow body with a red beak, and a hat clears the hair beneath it", () => {
  const all = Object.values(gearOf({ id: "duck" })!.front).join("")
  expect(all).toContain("y")
  expect(all).toContain("r")
  expect(all).toContain("_")
})

test("the fishbowl is see-through: it clears nothing, so the head shows inside the glass", () => {
  const g = gearOf({ id: "fishbowl" })!
  for (const view of ["front", "side", "back"] as const) expect({ view, cleared: Object.values(g[view]).join("").includes("_") }).toEqual({ view, cleared: false })
})

test("the snail's side view sits on the side torso (cols 3-8), not off to its left", () => {
  const side = gearOf({ id: "snail" })!.side
  for (const row of [10, 11]) {
    const cols = [...side[row]!].flatMap((c, i) => (c === "." ? [] : [i]))
    expect({ row, within: cols.every((i) => i >= 3 && i <= 8) }).toEqual({ row, within: true })
  }
})
