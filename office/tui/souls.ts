// The souls dir on disk. Kept out of kit/, which every surface bundles: the desktop's GJS has no node:fs.
import { readdirSync, readFileSync, statSync } from "node:fs"
import { join } from "node:path"
import { parseSoul, type Soul } from "../kit/souls"

const files = (dir: string) => { try { return readdirSync(dir).filter(f => f.endsWith(".md")).sort() } catch { return [] } }

/** names and mtimes of the dir's `<name>.md` files; "" when there are none, so a poll can tell a change from a quiet dir */
export function soulsSignature(dir: string): string {
  return files(dir).map(f => { try { return `${f}@${statSync(join(dir, f)).mtimeMs}` } catch { return f } }).join("|")
}

export function loadSouls(dir: string): Record<string, Soul> {
  const out: Record<string, Soul> = {}
  for (const f of files(dir)) {
    try { out[f.slice(0, -3)] = parseSoul(readFileSync(join(dir, f), "utf8")) } catch { /* unreadable: no soul, not a crash */ }
  }
  return out
}
