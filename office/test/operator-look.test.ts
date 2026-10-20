import { afterEach, expect, test } from "bun:test"
import { baseLook, bossLook, OPERATOR, useLookOverrides } from "../kit/looks"
import { BOSS_LOOK, lookOf } from "../kit/sprites"

afterEach(() => useLookOverrides({}))

test("the operator can change their own look: a looks.json entry under `operator` reaches the big desk's figure", () => {
  expect(bossLook()).toEqual(BOSS_LOOK)
  useLookOverrides({ [OPERATOR]: { hair: "bun", hairRole: "attention", accessory: "glasses" } })
  expect(bossLook()).toMatchObject({ hair: "bun", hairRole: "attention", accessory: "glasses", fav: BOSS_LOOK.fav })
})

test("an edit starts from who it is: the operator's own figure, a coworker's seeded one", () => {
  expect(baseLook(OPERATOR)).toEqual(BOSS_LOOK)
  expect(baseLook("hronir")).toEqual(lookOf("hronir"))
})
