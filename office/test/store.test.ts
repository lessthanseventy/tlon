import { expect, test } from "bun:test"
import { mkdtempSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { resolvePets, slotOf } from "../kit/pets"
import { adopt, back, candidateOf, emptyStore, loadStore, pass, rename, roll, saveStore, SHELF, shelve, storeNamesTaken, toggleLock, type Store } from "../kit/store"
import { loadPets, savePets } from "../tui/pets"

const s0: Store = { ...emptyStore(), species: "hamster" }
test("the same (species, seed, taken) is the same candidate", () => {
  expect(roll("hamster", "store:3", [])).toEqual(roll("hamster", "store:3", []))
  expect(roll("hamster", "store:3", []).name).toBeTruthy()
})
test("the axes stay in -2..2 and the shade in 0..3, over many seeds", () => {
  for (let n = 1; n < 200; n++) {
    const c = roll("rock", `store:${n}`, [])
    for (const a of Object.values(c.temperament)) expect(a >= -2 && a <= 2 && Number.isInteger(a)).toBe(true)
    expect(c.shade >= 0 && c.shade <= 3).toBe(true)
  }
})
test("names skip the taken ones", () => {
  const c = roll("hamster", "store:1", [])
  expect(roll("hamster", "store:1", [c.name]).name).not.toBe(c.name)
})
test("a pass keeps a locked row and moves the rest; back returns to the earlier seed", () => {
  const c0 = candidateOf(toggleLock(toggleLock(s0, "name"), "warmth"), [])
  const s1 = pass(toggleLock(toggleLock(s0, "name"), "warmth"), [])
  const c1 = candidateOf(s1, [])
  expect(c1.name).toBe(c0.name)
  expect(c1.temperament.warmth).toBe(c0.temperament.warmth)
  expect(s1.seed).toBe("store:2")
  expect(back(s1, []).seed).toBe("store:1")
  expect(back(s0, []).seed).toBe("store:1")
})
test("a locked name that is now taken is dropped, not kept", () => {
  const locked = toggleLock(s0, "name"), c = candidateOf(locked, [])
  expect(candidateOf(pass(locked, [c.name]), [c.name]).name).not.toBe(c.name)
})
test("shelve walks both families and wraps; locks carry", () => {
  expect(SHELF).toContain("hamster")
  expect(SHELF).toContain("dog")
  expect(new Set(SHELF.map((sp) => slotOf(sp)))).toEqual(new Set(["cat", "dog"]))
  let s = s0
  for (let i = 0; i < SHELF.length; i++) s = shelve(s, 1, [])
  expect(s.species).toBe("hamster")
  const named = rename(toggleLock(s0, "name"), "Biscuit")
  expect(candidateOf(shelve(named, 1, []), []).name).toBe("Biscuit")
})
test("a carried or typed name is checked against the taken list of the species on the card", () => {
  // shelve carries the lock with the cat family's taken list; the dog's card is read against the dog's
  const nina = shelve(rename(toggleLock(emptyStore(), "name"), "Nina"), 1, ["Argos"])
  expect(nina.species).toBe("dog")
  expect(candidateOf(nina, ["Nina"]).name).not.toBe("Nina")
  expect(candidateOf(rename(s0, "Ann"), ["Ann"]).name).not.toBe("Ann")
  expect(candidateOf(rename(s0, "Ann"), []).name).toBe("Ann")
})
test("adopt writes one slot; a species outside the slot is refused", () => {
  const c = candidateOf(rename(s0, "Biscuit"), [])
  expect(adopt(c, "cat")).toEqual({ cat: { name: "Biscuit", species: "hamster", temperament: c.temperament, shade: c.shade } })
  expect(adopt(c, "dog")).toBeNull()
  expect(adopt({ ...c, name: "  " }, "cat")).toBeNull()
  const d = candidateOf(rename({ ...s0, species: "dog" }, "Rex"), [])
  expect(adopt(d, "dog")).toEqual({ dog: { name: "Rex", species: "dog", temperament: d.temperament, shade: d.shade } })
  expect(adopt(d, "cat")).toBeNull()
})
test("an adopt through savePets replaces the cat and leaves the dog", () => {
  const dir = mkdtempSync(join(tmpdir(), "store-")), path = join(dir, "pets.json")
  try {
    savePets({ dog: { name: "Argos" } }, path)
    savePets(adopt(candidateOf(rename(s0, "Biscuit"), []), "cat")!, path)
    const p = resolvePets(loadPets(path))
    expect(p.cat.name).toBe("Biscuit"); expect(p.cat.species).toBe("hamster")
    expect(p.dog.name).toBe("Argos")
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
test("store.json round-trips and a damaged one is the empty store", () => {
  const dir = mkdtempSync(join(tmpdir(), "store-")), path = join(dir, "store.json")
  try {
    const s = rename(toggleLock(pass(s0, []), "shade"), "Mochi")
    saveStore(path, s)
    expect(loadStore(path)).toEqual(s)
    saveStore(path, { ...s, species: "dog" })
    expect(loadStore(path).species).toBe("dog")
    saveStore(path, { ...s, species: "unicorn" } as never)
    expect(loadStore(path).species).toBe("cat")
    expect(loadStore(join(dir, "none.json"))).toEqual(emptyStore())
  } finally { rmSync(dir, { recursive: true, force: true }) }
})
test("storeNamesTaken: the bench plus the OTHER slot's pet, never the occupant being replaced", () => {
  expect(storeNamesTaken(["Ann"], { cat: { name: "Nina" }, dog: { name: "Argos" } }, "dog")).toEqual(["Ann", "Nina"])
  expect(storeNamesTaken(["Ann"], { cat: { name: "Nina" }, dog: { name: "Argos" } }, "hamster")).toEqual(["Ann", "Argos"])
})
