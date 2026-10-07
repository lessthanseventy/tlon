// WCAG 2.2 AA for what the TUI shows: every label in the room, and every colour the panes set
// text in, reads at 4.5:1 or better (1.4.3).
import { describe, expect, test } from "bun:test"
import { viewOf } from "../kit/crew"
import { contrast, ROLE } from "../kit/palette"
import { EMPTY, type Agents } from "../kit/types"
import { RailRoom, W, H } from "../rooms/rail"
import { WideRoom, WIDE_H } from "../rooms/wide"
import { geometry, inkInto, measureFor, MIN_CONTRAST, textScale, typeFor } from "../tui/paint"

export function office(): Agents {
  const names = ["tertius", "hronir", "lonnrot", "yu", "ashe", "daneri"]
  return {
    ...EMPTY, ok: true, workspaces: [{ id: 1, name: "Machine" }],
    archetypes: [{ name: "surveyor", meta: true, read_only: true, model: "" }, { name: "builder", meta: false, read_only: false, model: "" }, { name: "reviewer", meta: false, read_only: true, model: "" }],
    bench: names.map((name, i) => ({ workspace_id: 1, seat_id: i, agent_id: i + 1, name, archetype: i === 0 ? "surveyor" : i === 2 ? "reviewer" : "builder", lead: i === 1, model: null, ask: null })),
    threads: names.map((name, i) => ({ id: 100 + i, title: `a thread about ${name}`, stage: ["build", "spec", null][i % 3] ?? null, awaiting: i === 3 ? "andrew" : null, workspace_id: 1, lead: name })),
    roster: names.map((name, i) => ({ agent: name, thread_id: 100 + i, title: `t${i}`, warm: i % 2 === 0, thinking: i % 2 === 0, workspace_id: 1 })),
    tickets: [{ id: 7, workspace_id: 1, project_id: null, title: "a ticket with a long title", priority: "high", routed: true }],
    notes: [{ id: 1, author: "hronir", body: "a note", workspace_id: 1, at: new Date().toISOString() }],
  }
}

/** every label the room drew, with the colour actually behind it once the painter has backed it */
function labels(room: RailRoom | WideRoom, w: number, h: number, cell: { w: number; h: number }, cols: number, rows: number) {
  const g = geometry(w, h, cols, rows, 17, cell, true), a = viewOf(office(), 1)
  for (let i = 0; i < 300; i++) room.step(a)
  room.say("yu", "a reply to you")
  const fr = room.render(a, { picked: 101, armed: null, person: null }, measureFor(g))
  const bw = fr.width * g.k, bh = fr.height * g.k, big = new Uint8Array(bw * bh * 4)
  for (let y = 0; y < bh; y++) for (let x = 0; x < bw; x++) big.set(fr.rgba.subarray(((Math.floor(y / g.k) * fr.width) + Math.floor(x / g.k)) * 4, ((Math.floor(y / g.k) * fr.width) + Math.floor(x / g.k)) * 4 + 4), (y * bw + x) * 4)
  const backed: { text: string; behind: string }[] = []
  inkInto(big, bw, bh, fr.ink, g.k, textScale(g), backed)
  return backed
}

describe("WCAG 1.4.3: text contrast", () => {
  test("every label in the wide room reads at 4.5:1 against what is behind it", () => {
    const got = labels(new WideRoom(696), 696, WIDE_H, { w: 8, h: 18 }, 174, 51)
    expect(got.length).toBeGreaterThan(20)
    for (const l of got) expect({ ...l, ratio: contrast(l.text, l.behind) >= MIN_CONTRAST }).toMatchObject({ ratio: true })
  })
  test("every label in the rail room too", () => {
    const got = labels(new RailRoom(), W, H, { w: 10, h: 20 }, 60, 70)
    expect(got.length).toBeGreaterThan(10)
    for (const l of got) expect({ ...l, ratio: contrast(l.text, l.behind) >= MIN_CONTRAST }).toMatchObject({ ratio: true })
  })
  test("every colour the panes set text in, on the terminal's dark ground; the badges' text on their fills", () => {
    const pane = [ROLE.prose, ROLE.inactive, ROLE.key, ROLE.attention, ROLE.body, ROLE.live, ROLE.alarm, ROLE.meta, ROLE.assistant, ROLE.builder, ROLE.reviewer, ROLE.planner, ROLE.surveyor]
    for (const c of pane) expect({ c, ratio: contrast(c, ROLE.ground) >= MIN_CONTRAST }).toMatchObject({ ratio: true })
    for (const fill of [ROLE.attention, ROLE.key]) expect({ fill, ratio: contrast(ROLE.ground, fill) >= MIN_CONTRAST }).toMatchObject({ ratio: true })
  })
})

describe("WCAG 1.4.8-ish: labels don't overprint each other", () => {
  test("no two labels in the wide room overlap, at the TUI's own type sizes", () => {
    // the room's width as the TUI picks it, at the terminal's zoom: 18 px cells, then zoomed in on narrow terminals
    for (const [w, ch, cols] of [[540, 18, 135], [696, 18, 174], [900, 18, 225], [720, 27, 120], [696, 27, 174], [640, 36, 120], [600, 45, 120]] as const) {
      const g = geometry(w, WIDE_H, cols, 51, 17, { w: Math.round((ch * 8) / 18), h: ch }, true), a = viewOf(office(), 1), room = new WideRoom(w)
      for (let i = 0; i < 300; i++) room.step(a)
      const zoom = textScale(g), boxes = room.render(a, { picked: 101, armed: null, person: null }, measureFor(g)).ink.flatMap((i) => {
        if (i.t !== "text") return []
        const { font, sc } = typeFor(i.size, zoom), tw = i.s.length * font.w * sc, x = i.align === "center" ? i.x * g.k - tw / 2 : i.x * g.k, base = i.y * g.k - sc
        return [{ s: i.s, x0: x, x1: x + tw - sc, y0: base - font.ascent * sc, y1: base + (font.h - font.ascent) * sc }]
      })
      const clashes = boxes.flatMap((p, n) => boxes.slice(n + 1).filter((q) => p.x0 < q.x1 && q.x0 < p.x1 && p.y0 < q.y1 && q.y0 < p.y1).map((q) => `${w} @${ch}px: "${p.s}" × "${q.s}"`))
      expect(clashes).toEqual([])
    }
  })
})
