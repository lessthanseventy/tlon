// The thread card's activity timeline (`tui/timeline.ts`): what a coworker did, from the server's
// feed, grouped by who did it, a rule between turns, newest at the bottom — and scrolled by the pane.
import { describe, expect, test } from "bun:test"
import { contrast, ROLE } from "../kit/palette"
import type { Activity } from "../kit/types"
import { offset } from "../tui/pane"
import { MIN_CONTRAST } from "../tui/paint"
import { KINDS, timelineRows } from "../tui/timeline"

const at = (m: number) => new Date(2026, 9, 8, 14, m).toISOString()
const ev = (agent: string, m: number, kind: string, summary: string): Activity => ({ thread_id: 1, agent, at: at(m), kind, summary })
const FEED: Activity[] = [
  ev("hronir", 0, "thinking", "thinking"),
  ev("hronir", 1, "read", "Read · lib/server/ticket.ex"),
  ev("hronir", 2, "edit", "Edit · office/kit/crew.ts"),
  ev("tertius", 3, "test", "Bash · mise run check"),
  ev("hronir", 4, "thinking", "thinking"),
  ev("hronir", 5, "bash", "Bash · git status"),
]
const SHIRTS: Record<string, string> = { hronir: ROLE.builder, tertius: ROLE.reviewer }
const opts = { width: 60, colorOf: (a: string) => SHIRTS[a]!, live: new Set<string>(), clock: (s: string) => s.slice(11, 16) }
const text = (rows: { segs: { s: string }[] }[]) => rows.map((r) => r.segs.map((g) => g.s).join(""))

describe("the activity timeline", () => {
  test("groups a run of one coworker's events under their name, a rule between turns, newest last", () => {
    const t = text(timelineRows(FEED, opts))
    expect(t.filter((l) => l.startsWith("  hronir")).length).toBe(2) // a header per run, not per event
    expect(t.filter((l) => l.startsWith("  tertius")).length).toBe(1)
    expect(t.filter((l) => l.includes("╌")).length).toBe(2) // each fresh turn
    expect(t.findIndex((l) => l.includes("lib/server/ticket.ex"))).toBeLessThan(t.findIndex((l) => l.includes("mise run check")))
    expect(t.at(-1)).toContain("git status")
  })

  test("each kind has its own glyph and colour, the target highlighted in it; the tool in prose", () => {
    const glyphs = Object.values(KINDS).map((k) => k.glyph), main = ["read", "edit", "bash", "test", "search", "web"]
    expect(new Set(glyphs).size).toBe(glyphs.length)
    expect(new Set(main.map((k) => ROLE[KINDS[k]!.role])).size).toBe(main.length)
    const row = timelineRows([ev("hronir", 2, "edit", "Edit · office/kit/crew.ts")], opts).at(-1)!
    const target = row.segs.find((g) => g.s.includes("office/kit/crew.ts"))!, tool = row.segs.find((g) => g.s === "Edit")!
    expect(target).toMatchObject({ fg: ROLE[KINDS.edit!.role], bold: true })
    expect(tool.fg).toBe(ROLE.prose)
    expect(row.segs.find((g) => g.s.includes("14:02"))!.fg).toBe(ROLE.inactive)
  })

  test("the agent's name in their own colour", () => {
    const rows = timelineRows(FEED, opts)
    const name = (a: string) => rows.flatMap((r) => r.segs).find((g) => g.s.trim() === a)!
    expect(name("hronir")).toMatchObject({ fg: ROLE.builder, bold: true })
    expect(name("tertius")).toMatchObject({ fg: ROLE.reviewer, bold: true })
  })

  test("the newest line is marked, with a live dot while its coworker is mid-turn", () => {
    expect(text(timelineRows(FEED, opts)).at(-1)!.startsWith("▸")).toBe(true)
    const live = timelineRows(FEED, { ...opts, live: new Set(["hronir"]) }).at(-1)!
    expect(live.segs[0]).toMatchObject({ s: expect.stringContaining("●"), fg: ROLE.live })
    expect(text(timelineRows(FEED, opts)).slice(0, -1).some((l) => l.startsWith("▸"))).toBe(false)
  })

  test("a long line is cut to the card's width", () => {
    const long = timelineRows([ev("hronir", 1, "bash", `Bash · ${"x".repeat(200)}`)], opts)
    for (const l of text(long)) expect([...l].length).toBeLessThanOrEqual(opts.width)
  })

  test("every colour it sets text in reads at 4.5:1 on the terminal's ground", () => {
    for (const r of timelineRows(FEED, { ...opts, live: new Set(["hronir"]) })) for (const g of r.segs) if (g.fg) expect({ fg: g.fg, ok: contrast(g.fg, ROLE.ground) >= MIN_CONTRAST }).toMatchObject({ ok: true })
  })

  test("the pane opens on the newest lines and scrolls back to the oldest", () => {
    const many = Array.from({ length: 60 }, (_, i) => ev("hronir", i % 60, "read", `Read · file${i}.ex`))
    const rows = text(timelineRows(many, opts)), room = 10
    const bottom = offset(rows.length, room, Infinity)
    expect(rows.slice(bottom.first, bottom.first + bottom.count).at(-1)).toContain("file59.ex")
    const top = offset(rows.length, room, 0)
    expect(rows.slice(top.first, top.first + top.count).join("\n")).toContain("file0.ex")
  })
})
