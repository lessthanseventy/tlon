import { afterAll, expect, test } from "bun:test"
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { started, TUI_TEST } from "./started"
import { waitFor } from "./wait-for"

// The cast editor in --sandbox writes its cast.json under $TMPDIR/tlon-sandbox, never the operator's config dir.
const socket = `tlon-office-cast-sandbox-${process.pid}`
const tmp = mkdtempSync(join(tmpdir(), "office-cast-sb-")), config = mkdtempSync(join(tmpdir(), "office-cast-sb-config-"))
const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
afterAll(() => {
  tmux("kill-server")
  rmSync(`${process.env.TMUX_TMPDIR ?? "/tmp"}/tmux-${process.getuid!()}/${socket}`, { force: true })
  rmSync(tmp, { recursive: true, force: true })
  rmSync(config, { recursive: true, force: true })
})

const dec = new TextDecoder()
const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)

test("⏎ on grade in the sandbox keeps it in the sandbox's cast.json, and the operator's config dir stays empty", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && env -u TLON_CAST -u TLON_LOOKS -u TLON_SOULS TMPDIR='${tmp}' XDG_CONFIG_HOME='${config}' XDG_STATE_HOME='${tmp}' OFFICE_GRAPHICS=blocks OFFICE_NO_ANIMATE=1 '${process.execPath}' tui/main.ts --sandbox`)
  await started(tmux, "the room", () => screen().includes("HOME"))
  tmux("send-keys", "-t", "0", "-l", "`")
  await waitFor(screen, "THE CAST · people", "the cast")
  // One → per field, each waited on: a key sent before the last one's repaint is seen would walk past grade under load.
  for (const f of ["archetype", "look", "soul", "voice", "grade"]) {
    tmux("send-keys", "-t", "0", "right")
    await waitFor(screen, `THE CAST · people · ${f}`, `${f} lit`)
  }
  tmux("send-keys", "-t", "0", "enter")
  const file = join(tmp, "tlon-sandbox", "cast.json")
  await waitFor(screen, () => existsSync(file), "the sandbox's cast.json")
  expect(Object.values(JSON.parse(readFileSync(file, "utf8")) as Record<string, { grade?: string }>).map((t) => t.grade)).toEqual(["junior"])
  expect(readdirSync(config)).toEqual([])
}, TUI_TEST)
