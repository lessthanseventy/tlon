#!/usr/bin/env bun
// import-sprite: a PNG (12x22, one view, or 48x22, four views side by side) → looks.json's
// `custom` field for an agent, every pixel snapped to the nearest role via kit/snap.ts.
// The only file in office/ that imports pngjs — kept out of kit/ and tui/ so the compiled TUI's
// one runtime dep (office/AGENTS.md) stays just that.
import { PNG } from "pngjs"
import { readFileSync, writeFileSync } from "node:fs"
import { homedir } from "node:os"
import { join } from "node:path"
import { nearestChar } from "./kit/snap"
import { figure, lookOf, paints, shirtOf, type Look } from "./kit/sprites"

const VIEWS = ["front", "side", "back", "side"] as const // the 48x22 sheet's four columns; the 4th (back-right) is unused today

export function snapSheet(buf: Buffer, w: number, h: number, paint: Record<string, string>): string[] {
  if (h !== 22 || (w !== 12 && w !== 48)) throw new Error(`expected 12x22 or 48x22, got ${w}x${h}`)
  const png = PNG.sync.read(buf), rows: string[] = []
  for (let y = 0; y < h; y++) {
    let row = ""
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4
      row += nearestChar(`#${[0, 1, 2].map((k) => png.data[i + k]!.toString(16).padStart(2, "0")).join("")}`, paint, png.data[i + 3]!)
    }
    rows.push(row)
  }
  return rows
}

function sheetToViews(rows: string[], w: number): Partial<Record<"front" | "side" | "back", string[]>> {
  if (w === 12) return { front: rows }
  const out: Partial<Record<"front" | "side" | "back", string[]>> = {}
  for (let v = 0; v < 3; v++) out[VIEWS[v]!] = rows.map((r) => r.slice(v * 12, v * 12 + 12))
  return out
}

/** a coworker's standing figure, front view, as the office draws it: its rows and the paint for each letter */
export function figureOf(name: string, archetype: string | null): { rows: string[]; paint: Record<string, string> } {
  const look = lookOf(name)
  return { rows: figure(look, archetype, false, false, "down", "stand", 0, false), paint: paints(shirtOf(archetype), look) }
}

if (import.meta.main && process.argv[2] === "figure") {
  // the tlon-citizen mod draws its coworker from this, so the office's art has one source
  const [, , , name, archetype] = process.argv
  if (!name) { console.error("usage: figure <agent-name> [archetype]"); process.exit(1) }
  console.log(JSON.stringify(figureOf(name, archetype ?? null)))
  process.exit(0)
}

if (import.meta.main) {
  const [cmd, path, name] = process.argv.slice(2)
  if (cmd !== "import-sprite" || !path || !name) { console.error("usage: import-sprite <path.png> <agent-name> | figure <agent-name> [archetype]"); process.exit(1) }
  const buf = readFileSync(path), { width, height } = PNG.sync.read(buf)
  const current: Look = lookOf(name)
  const paint = paints(shirtOf(null), current)
  let rows: string[]
  try { rows = snapSheet(buf, width, height, paint) } catch (e) { console.error((e as Error).message); process.exit(1) }
  for (const r of rows) console.log(r)
  const looksPath = process.env.TLON_LOOKS ?? join(process.env.XDG_CONFIG_HOME ?? join(homedir(), ".config"), "tlon/looks.json")
  const all = JSON.parse((() => { try { return readFileSync(looksPath, "utf8") } catch { return "{}" } })())
  all[name] = { ...all[name], custom: sheetToViews(rows, width) }
  writeFileSync(looksPath, JSON.stringify(all, null, 2))
  console.log(`wrote ${looksPath} (${name})`)
}
