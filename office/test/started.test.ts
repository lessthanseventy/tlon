import { afterAll, expect, test } from "bun:test"
import { killServer } from "./kill-server"
import { started } from "./started"

// A TUI start is waited on with its own budget, longer than a step's, and a pane whose process has
// already gone (tmux closed its window) fails at once instead of waiting that budget out.
const dec = new TextDecoder()
const sockets: string[] = []
const session = (cmd: string) => {
  const socket = `tlon-office-started-${process.pid}-${sockets.length}`
  sockets.push(socket)
  const tmux = (...a: string[]) => Bun.spawnSync(["tmux", "-L", socket, ...a])
  tmux("new-session", "-d", "-x", "80", "-y", "24", cmd)
  const screen = () => dec.decode(tmux("capture-pane", "-p", "-t", "0").stdout)
  return { tmux, screen }
}
afterAll(() => { for (const s of sockets) killServer(s) })

test("a start that paints within the budget resolves", async () => {
  const { tmux, screen } = session("sleep 1; echo READY; sleep 30")
  await started(tmux, "the ready line", () => screen().includes("READY"))
  expect(screen()).toContain("READY")
})

test("a pane whose process exited fails at once, naming it, not after the budget", async () => {
  const { tmux, screen } = session("true")
  const t0 = performance.now()
  await expect(started(tmux, "anything", () => screen().includes("never"))).rejects.toThrow(/pane is gone/)
  expect(performance.now() - t0).toBeLessThan(10_000)
})

test("a start that never paints what was asked fails after the budget with the pane", async () => {
  const { tmux, screen } = session("echo SOMETHING ELSE; sleep 30")
  const t0 = performance.now()
  await expect(started(tmux, "the ready line", () => screen().includes("READY"), 800)).rejects.toThrow(/never saw the ready line[\s\S]*SOMETHING ELSE/)
  expect(performance.now() - t0).toBeGreaterThanOrEqual(800)
})
