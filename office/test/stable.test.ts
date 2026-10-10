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
  }, 30_000) // thousands of figures drawn: over bun's 5 s default on a busy machine
  test("a name still hashes to the same hair and hair colour, and to no new field", () => {
    const want: Record<string, [string, string]> = {
      tertius: ["long", "meta"], hronir: ["mop", "inactive"], lonnrot: ["bun", "borderInactive"], yu: ["mop", "structure"],
      ashe: ["spiky", "meta"], daneri: ["bun", "inactive"], quain: ["mop", "meta"], uqbar: ["mop", "structure"],
    }
    for (const [n, [hair, hairRole]] of Object.entries(want)) {
      const l = lookOf(n)
      expect([l.hair, l.hairRole] as string[]).toEqual([hair, hairRole])
      expect(l.body).toBeUndefined()
      expect(l.parts).toBeUndefined()
    }
  })
})
