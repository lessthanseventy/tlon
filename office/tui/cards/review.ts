import { ROLE } from "../../kit/palette"
import * as data from "../data"
import { bind } from "../keys"
import { type Mode, type Row, type Card } from "../state"
import { waiting } from "../select"
import { dim, key, plain } from "../ui"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function reviewCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "review" }>): Card {
  const tid = mode.tid, notes = app.reviewNotes.get(tid) ?? []
  if (!app.review) return { title: `REVIEW · #${tid}`, rows: [{ segs: [waiting(app, "reading the branch…")] }], actions: [ctl.back1] }
  type At = { path: string; line?: number; side?: "+" | "-" | " "; hunk?: boolean }
  const same = (n: data.ReviewNote, at: At) => n.path === at.path && n.line === at.line && n.side === at.side
  const rows: Row[] = []
  const noteRows = (at: At) => { for (const n of notes) if (same(n, at)) rows.push({ segs: [dim("        "), { s: `✎ ${n.text}`, fg: ROLE.attention }], ref: at }) }
  const noteOn = (at: At) => ctl.ask(at.line ? `note on ${at.path}:${at.line}` : `note on ${at.path}`, (s) => {
    if (!s.trim()) return
    app.reviewNotes.set(tid, [...(app.reviewNotes.get(tid) ?? []).filter((n) => !same(n, at)), { path: at.path, line: at.line, side: at.side, text: s.trim() }]); ctl.draw()
  }, { text: notes.find((n) => same(n, at))?.text ?? "" })
  for (const f of app.review.files) {
    const at: At = { path: f.path }
    rows.push({ segs: [key(f.path), dim(`  ${f.status}  `), { s: `+${f.added}`, fg: ROLE.live }, plain(" "), { s: `-${f.deleted}`, fg: ROLE.attention }, ...(f.binary ? [dim("  binary")] : [])], open: () => noteOn(at), ref: at })
    noteRows(at)
    for (const h of f.hunks) {
      rows.push({ segs: [dim(h.header)], ref: { path: f.path, hunk: true } })
      for (const l of h.lines) {
        const lineAt: At = { path: f.path, line: l.new ?? l.old ?? undefined, side: l.kind }
        const num = (n: number | null) => (n === null ? "    " : String(n).padStart(4))
        rows.push({ segs: [dim(`${num(l.old)} ${num(l.new)} `), { s: `${l.kind}${l.text}`, fg: l.kind === "+" ? ROLE.live : l.kind === "-" ? ROLE.attention : ROLE.prose }], open: () => noteOn(lineAt), ref: lineAt })
        noteRows(lineAt)
      }
    }
  }
  if (!app.review.files.length) rows.push({ segs: [dim("the branch changes nothing yet")] })
  const here = rows[app.sel]?.ref as At | undefined
  const jump = (dir: 1 | -1, want: (a: At, i: number) => boolean) => {
    for (let i = app.sel + dir; i >= 0 && i < rows.length; i += dir) if (rows[i]?.ref && want(rows[i]!.ref as At, i)) { app.sel = i; return ctl.draw() }
  }
  const isFile = (a: At) => !a.line && !a.hunk
  const submit = () => ctl.ask(`review #${tid}: a summary (optional) · tab: the verdict`, (s, [verdict]) => {
    const sent = data.reviewSubmit(tid, verdict as string, s, app.reviewNotes.get(tid) ?? [])
    // the notes are kept until the server takes them: a refused submit loses nothing
    void ctl.did(sent.then((msg) => { if (!msg.includes(" failed: ")) { app.reviewNotes.delete(tid); ctl.back() } return msg }))
  }, { cycles: [{ name: "verdict", values: [{ label: "comment", value: "comment" }, { label: "request changes", value: "changes" }, { label: "approve", value: "approve" }], i: 0 }] })
  return {
    title: `REVIEW · #${tid}${app.review.head ? ` @ ${app.review.head.slice(0, 7)}` : ""} · ${app.review.files.length} files · ${notes.length} notes · ⏎ notes the selected line`,
    rows,
    actions: [
      { ...bind("review.a"), run: () => { if (here && !here.hunk) noteOn(here) } },
      { ...bind("review.A"), run: () => { if (here) noteOn({ path: here.path }) } },
      ...(here && notes.some((n) => same(n, here)) ? [{ ...bind("review.x"), run: () => { app.reviewNotes.set(tid, notes.filter((n) => !same(n, here))); ctl.draw() } }] : []),
      { ...bind("review.n"), run: () => jump(1, (a) => !!a.hunk) }, { ...bind("review.p"), run: () => jump(-1, (a) => !!a.hunk) },
      { ...bind("review.N"), run: () => jump(1, isFile) }, { ...bind("review.P"), run: () => jump(-1, isFile) },
      { ...bind("review.s", `submit${notes.length ? ` ${notes.length} notes` : ""}…`), run: submit },
      ctl.back1,
    ],
  }
}
