// Wait until the TUI's screen shows what a step needs, instead of sleeping and hoping. `want` is
// text the screen contains, a pattern it matches, or a test of the whole screen.
export type Want = string | RegExp | ((screen: string) => boolean)

const holds = (want: Want, screen: string) =>
  typeof want === "string" ? screen.includes(want) : want instanceof RegExp ? want.test(screen) : want(screen)

export const waitFor = async (screen: () => string, want: Want, what = String(want), budget = 25_000) => {
  const t0 = performance.now()
  while (!holds(want, screen())) {
    const ms = Math.round(performance.now() - t0)
    if (ms >= budget) throw new Error(`never saw ${what} after ${ms}ms; pane:\n${screen()}`)
    await Bun.sleep(50)
  }
}
