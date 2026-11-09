import { expect, test } from "bun:test"
import { Glob } from "bun"
import { join } from "node:path"

// kit/, rooms/ and tui/ draw chance through kit/rng.ts alone, so a test can pin every roll in one place.
test("no Math.random under kit/, rooms/ or tui/ outside kit/rng.ts", async () => {
  const root = join(import.meta.dir, "..")
  const bad: string[] = []
  for (const dir of ["kit", "rooms", "tui"]) {
    for await (const file of new Glob(`${dir}/**/*.ts`).scan(root)) {
      if (file === "kit/rng.ts") continue
      const lines = (await Bun.file(join(root, file)).text()).split("\n")
      lines.forEach((l, i) => { if (l.includes("Math.random")) bad.push(`${file}:${i + 1}`) })
    }
  }
  expect(bad).toEqual([])
})
