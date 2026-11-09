import { CELL, OFFICE_ROWS, defaultHome, drop, move, pickUp, place, remove, rotate, startBuild, undo, type Build } from "../../kit/home"
import { corkLabel } from "../../kit/souls"
import { ROLE } from "../../kit/palette"
import { shirtOf } from "../../kit/sprites"
import { type Agents } from "../../kit/types"
import * as data from "../data"
import { bind } from "../keys"
import { applyBuild, loadFloor } from "../home"
import { arrange, next } from "../order"
import { TRAY_SORTS, type Row, type Card } from "../state"
import { waiting, wsName } from "../select"
import { ago, dim, key, plain } from "../ui"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export const KIND: Record<string, string> = { message: "said", fact: "learned", issue: "raised", question: "asked", check_failed: "check failed", check_passed: "check passed", work_landed: "landed", stage_advanced: "advanced", handoff_opened: "handed off" }

export function archiveCard(app: State, ctl: Ctl): Card {
  if (!app.archived) return { title: "FILING CABINET", rows: [{ segs: [waiting(app, "opening the drawers…")] }], actions: [ctl.back1] }
  const day = (s: string | null) => (s ? s.slice(0, 10) : "")
  const rows: Row[] = [{ segs: [key(`TICKETS DONE · ${app.archived.tickets.length}`)] }]
  for (const t of app.archived.tickets) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${day(t.closed_at)}`)] })
  rows.push({ segs: [key(`THREADS CLOSED · ${app.archived.threads.length}`)] })
  for (const t of app.archived.threads) rows.push({ segs: [dim(`#${t.id} `), plain(t.title), dim(`  ${t.stage ?? ""} ${day(t.at)}`)], open: () => ctl.openReader(t.id) })
  return { title: "FILING CABINET", rows, actions: [ctl.back1] }
}

export function notesCard(app: State, ctl: Ctl, a: Agents): Card {
  const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
  const rows: Row[] = a.notes.map((n) => ({ segs: [who(n.author), plain(n.body.replace(/\s+/g, " "))] }))
  // the crew's chatter, apart from the notes they work from (their suggestions go in the box)
  if (app.cork.length) rows.push({ segs: [key(`CORKBOARD · ${app.cork.length} — the crew's notes to each other`)] }, ...app.cork.map((n): Row => ({ segs: [dim(`${corkLabel(app.cork, n).padEnd(10)} `), who(n.author), plain(n.body), dim(n.re ? `  (re #${n.re})` : "")], ref: n })))
  return { title: `NOTES · ${a.notes.length}`, rows, actions: [{ ...bind("notes.n"), run: ctl.newNote }, ctl.back1] }
}

export function trayCard(app: State, ctl: Ctl): Card {
  const rows = arrange(app.feed, app.traySort.cmp, null)[0]!.items.map((x): Row => ({
    segs: [dim(ago(x.at).padStart(4) + " "), x.thread_id ? key(`#${x.thread_id} `) : dim(""), { s: `${x.who ?? ""} ${KIND[x.kind] ?? x.kind.replace(/_/g, " ")} `, fg: x.kind === "issue" || x.kind === "check_failed" ? ROLE.alarm : x.kind === "question" ? ROLE.attention : ROLE.inactive }, plain(x.text.replace(/\s+/g, " "))],
    open: x.thread_id ? () => ctl.openReader(x.thread_id!) : undefined, ref: `${x.at}${x.kind}${x.text}`,
  }))
  return {
    title: `IN-TRAY · ${wsName(app)}${app.traySort.name === "newest" ? "" : ` · by ${app.traySort.name}`}`, rows: rows.length ? rows : [{ segs: [dim("nothing yet")] }],
    actions: [{ ...bind("tray.s", `sort: ${app.traySort.name} → ${next(TRAY_SORTS, app.traySort).name}`), run: () => ctl.resort(() => { app.traySort = next(TRAY_SORTS, app.traySort) }) }, ctl.back1],
  }
}

export function memoryCard(app: State, ctl: Ctl): Card {
  if (!app.shelf) return { title: "MEMORY", rows: [{ segs: [waiting(app, "taking the books down…")] }], actions: [ctl.back1] }
  const rows: Row[] = [{ segs: [dim(`${app.shelf.coverage.facts} facts, ${app.shelf.coverage.embedded} embedded · pinned ${app.shelf.coverage.pinned_count} (~${app.shelf.coverage.pinned_tokens} of ${app.shelf.coverage.budget} tokens)`)] }]
  rows.push({ segs: [key(`HABITS TO REVIEW · ${app.shelf.habits.length}`)] })
  for (const h of app.shelf.habits) rows.push({ segs: [dim(`  ${h.by ?? "?"}: `), plain(h.text)], open: () => void 0, ref: { habit: h } })
  rows.push({ segs: [key(`PINNED — every session loads these · ${app.shelf.pinned.length}`)] })
  for (const f of app.shelf.pinned) rows.push({ segs: [dim(`  ${f.id} `), plain(f.text.replace(/\s+/g, " "))], open: () => void 0, ref: { fact: f } })
  const at = rows[app.sel]?.ref as { habit?: data.Memory["habits"][number]; fact?: data.Memory["pinned"][number] } | undefined
  const reload = () => void ctl.loadCard().then(ctl.draw)
  return {
    title: "MEMORY", rows,
    actions: [
      ...(at?.habit ? [{ ...bind("memory.a"), run: () => void ctl.did(data.habit(at.habit!.id, "approve")).then(reload) }, { ...bind("memory.r"), run: () => void ctl.did(data.habit(at.habit!.id, "reject")).then(reload) }] : []),
      ...(at?.fact ? [{ ...bind("memory.d"), run: () => ctl.ask2(`forget "${at.fact!.text.slice(0, 50)}"`, () => void ctl.did(data.forget(at.fact!.id)).then(reload)) }] : []),
      ctl.back1,
    ],
  }
}

export function buildCard(app: State, ctl: Ctl): Card {
  if (!app.build) { const h = loadFloor(); app.build = startBuild(h.tiles.length ? h : defaultHome(Math.ceil(app.g.floorW / CELL)), OFFICE_ROWS) }
  const b = app.build
  const mutate = (f: (b: Build) => Build): (() => void) => () => {
    app.build = applyBuild(app.build!, f)
    ctl.draw()
  }
  const rows: Row[] = [{ segs: [dim("the home is drawn above")] }]
  return {
    title: `BUILD MODE${b.carrying ? ` · carrying ${b.carrying.kind}` : ""}${b.refused ? " · refused — overlap or it would split the floor" : ""}`,
    rows,
    actions: [
      { ...bind("build.up"), run: mutate((x) => move(x, 0, -1)) },
      { ...bind("build.down"), run: mutate((x) => move(x, 0, 1)) },
      { ...bind("build.left"), run: mutate((x) => move(x, -1, 0)) },
      { ...bind("build.right"), run: mutate((x) => move(x, 1, 0)) },
      { ...bind("build.enter", b.carrying ? "drop" : "pick up"), run: mutate((x) => (x.carrying ? drop(x) : pickUp(x))) },
      { ...bind("build.n"), run: mutate((x) => place(x)) },
      { ...bind("build.x"), run: mutate((x) => remove(x)) },
      { ...bind("build.r"), run: mutate((x) => rotate(x)) },
      { ...bind("build.u"), run: mutate((x) => undo(x)) },
      { ...bind("build.esc"), run: () => { ctl.back(true); app.roomChanged = true; ctl.draw() } },
    ],
  }
}
