// A thread's activity feed as the card's timeline: who did what, a run of one coworker's events under
// their name, a rule where a fresh turn began, newest at the bottom (the pane opens there and scrolls back).
import { ROLE, type Role } from "../kit/palette"
import type { Activity } from "../kit/types"
import type { Seg } from "./term"

/** a kind's badge: a glyph (so no kind is told by colour alone) and the role it is drawn in */
export const KINDS: Record<string, { glyph: string; role: Role }> = {
  read: { glyph: "≡", role: "key" },
  edit: { glyph: "✎", role: "body" },
  bash: { glyph: "$", role: "meta" },
  test: { glyph: "✓", role: "live" },
  search: { glyph: "⌕", role: "assistant" },
  web: { glyph: "◎", role: "planner" },
  delegate: { glyph: "⇢", role: "surveyor" },
  post: { glyph: "✉", role: "prose" },
  tool: { glyph: "•", role: "inactive" },
}

export type TimelineOpts = {
  /** the row's width in cells: a longer line is cut */
  width: number
  /** a coworker's colour (their shirt) */
  colorOf: (agent: string) => string
  /** who is mid-turn on this thread: the newest line gets a live dot instead of the plain marker */
  live: Set<string>
  /** an event's time as shown */
  clock?: (at: string) => string
}

const hhmm = (at: string) => {
  const d = new Date(at), p = (n: number) => String(n).padStart(2, "0")
  return `${p(d.getHours())}:${p(d.getMinutes())}`
}
const dim = (s: string): Seg => ({ s, fg: ROLE.inactive })

/** the feed (oldest first) as the card's rows */
export function timelineRows(feed: Activity[], o: TimelineOpts): { segs: Seg[] }[] {
  const clock = o.clock ?? hhmm, out: { segs: Seg[] }[] = []
  let who: string | null = null
  feed.forEach((e, i) => {
    if (e.kind === "thinking") {
      const label = ` ${e.agent} · new turn ${clock(e.at)} `
      out.push({ segs: [dim(`╌╌${label}${"╌".repeat(Math.max(2, o.width - label.length - 2))}`.slice(0, o.width))] })
      who = null
      return
    }
    if (e.agent !== who) {
      out.push({ segs: [{ s: `  ${e.agent}`, fg: o.colorOf(e.agent), bold: true }, dim(`  ${clock(e.at)}`)] })
      who = e.agent
    }
    const k = KINDS[e.kind] ?? KINDS.tool!, fg = ROLE[k.role]
    const newest = i === feed.length - 1
    const mark: Seg = newest ? (o.live.has(e.agent) ? { s: "● ", fg: ROLE.live } : { s: "▸ ", fg: ROLE.key }) : { s: "  " }
    const cut = e.summary.indexOf(" · ")
    const tool = cut < 0 ? e.summary : e.summary.slice(0, cut), target = cut < 0 ? "" : e.summary.slice(cut + 3)
    const head = `${mark.s}  ${clock(e.at)} ${k.glyph} ${tool}`
    const room = Math.max(0, o.width - [...head].length - 3)
    const shown = [...target].length > room ? `${[...target].slice(0, Math.max(0, room - 1)).join("")}…` : target
    out.push({
      segs: [
        mark, dim(`  ${clock(e.at)} `), { s: k.glyph, fg, bold: true }, { s: " " }, { s: tool, fg: ROLE.prose },
        ...(target ? [dim(" · "), { s: shown, fg, bold: true }] : []),
      ],
    })
  })
  return out
}
