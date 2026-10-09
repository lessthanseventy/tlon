/** the wall poster's lines: one per local day, in order, so it is the same all day and new tomorrow */
export const POSTERS = [
  "Small commits, often.",
  "Evidence before assertions.",
  "Green before you commit.",
  "Ask, don't guess silently.",
  "Fix it or name it open.",
  "Rebase, then fast-forward.",
  "Run once, read the log.",
]

export function posterOf(now: Date): string {
  const day = Math.floor(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86_400_000)
  return POSTERS[day % POSTERS.length]!
}
