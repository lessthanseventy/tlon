import { afterAll, expect, test } from "bun:test"
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

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
const until = async (what: string, ok: () => boolean) => {
  const t0 = performance.now(), deadline = t0 + 15_000
  while (!ok() && performance.now() < deadline) await Bun.sleep(50)
  if (!ok()) throw new Error(`never saw ${what} after ${performance.now() - t0}ms; pane:\n${screen()}`)
}

test("⏎ on grade in the sandbox keeps it in the sandbox's cast.json, and the operator's config dir stays empty", async () => {
  const office = join(import.meta.dir, "..")
  tmux("new-session", "-d", "-x", "150", "-y", "50",
    `cd '${office}' && env -u TLON_CAST -u TLON_LOOKS -u TLON_SOULS TMPDIR='${tmp}' XDG_CONFIG_HOME='${config}' XDG_STATE_HOME='${tmp}' OFFICE_GRAPHICS=blocks '${process.execPath}' tui/main.ts --sandbox`)
  await until("the room", () => screen().includes("HOME"))
  tmux("send-keys", "-t", "0", "-l", "`")
  await until("the cast", () => screen().includes("THE CAST · people"))
  for (let i = 0; i < 8 && !screen().includes("THE CAST · people · grade"); i++) { tmux("send-keys", "-t", "0", "right"); await Bun.sleep(150) }
  await until("grade lit", () => screen().includes("THE CAST · people · grade"))
  tmux("send-keys", "-t", "0", "enter")
  const file = join(tmp, "tlon-sandbox", "cast.json")
  await until("the sandbox's cast.json", () => existsSync(file))
  expect(Object.values(JSON.parse(readFileSync(file, "utf8")) as Record<string, { grade?: string }>).map((t) => t.grade)).toEqual(["junior"])
  expect(readdirSync(config)).toEqual([])
}, 40_000)
