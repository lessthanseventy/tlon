// Waiting for the TUI's first paint. The TUI is a cold `bun tui/main.ts` in a tmux pane: alone it
// paints within a second, but the gate runs every suite at once on one box, and starved of CPU the
// same start has taken over 25 s. So a start is waited on with its own budget, never a step's, and
// a test that starts the TUI gives bun the room for it (TUI_TEST). A pane whose process is gone
// (tmux closes its window, and the server with it) fails at once, not after the budget.
export const STARTED = 120_000
export const TUI_TEST = STARTED + 60_000

type Tmux = (...args: string[]) => { exitCode: number; stdout: Uint8Array; stderr: Uint8Array }
const dec = new TextDecoder()

export const started = async (tmux: Tmux, what: string, ok: () => boolean, budget = STARTED) => {
  const t0 = performance.now()
  for (;;) {
    if (ok()) return
    const pane = tmux("capture-pane", "-p", "-t", "0")
    const ms = Math.round(performance.now() - t0)
    if (pane.exitCode !== 0) throw new Error(`the TUI's pane is gone after ${ms}ms (its process exited); tmux: ${dec.decode(pane.stderr).trim() || "(nothing)"}`)
    if (ms >= budget) throw new Error(`never saw ${what} after ${ms}ms of a ${budget}ms start budget; pane:\n${dec.decode(pane.stdout)}`)
    await Bun.sleep(50)
  }
}
