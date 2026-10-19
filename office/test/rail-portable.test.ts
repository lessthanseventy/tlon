import { expect, test } from "bun:test"
import { dirname, join } from "node:path"

// The desktop shell bundles rooms/rail.ts and everything it imports under GJS, which has no node:*.
// A node import anywhere in that graph breaks the shell's build, not this suite, so it is asserted here.
test("rooms/rail.ts and its whole import graph import nothing from node:", async () => {
  const seen = new Set<string>(), bad: string[] = []
  const walk = async (file: string) => {
    if (seen.has(file)) return
    seen.add(file)
    const src = await Bun.file(file).text()
    for (const [, spec] of src.matchAll(/^import\s[^"']*["']([^"']+)["']/gm)) {
      if (spec!.startsWith("node:")) bad.push(`${file}: ${spec}`)
      else if (spec!.startsWith(".")) await walk(join(dirname(file), spec!) + ".ts")
    }
  }
  await walk(new URL("../rooms/rail.ts", import.meta.url).pathname)
  expect(seen.size).toBeGreaterThan(3)
  expect(bad).toEqual([])
})
