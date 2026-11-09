import { resetToPreset, whimsyRows, whimsyTitle } from "../whimsy-card"
import { needsYou } from "../../kit/crew"
import { OPERATOR as MY_LOOK } from "../../kit/looks"
import { ROLE } from "../../kit/palette"
import * as data from "../data"
import { bind } from "../keys"
import { type Row, type Card } from "../state"
import { dim, key, pink, plain } from "../ui"
import { waiting, wsName } from "../select"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function bossCard(app: State, ctl: Ctl): Card {
  const w = app.ws
  const rows: Row[] = [{ segs: [plain(app.all.awaiting ? `${app.all.awaiting} thread(s) wait on you across the office` : "nothing waits on you")] }]
  for (const x of app.all.workspaces) {
    const n = app.all.threads.filter((t) => t.workspace_id === x.id && needsYou(t)).length, s = app.all.triage[String(x.id)] ?? 0
    rows.push({ segs: [key(x.id === app.ws ? "◆ " : "  "), plain(x.name.padEnd(16)), n ? pink(`${n} waiting  `) : dim(""), s ? dim(`${s} issues`) : dim("")], open: () => ctl.goWs(x.id) })
  }
  return {
    title: "WORKSPACES", rows,
    actions: [
      {
        ...bind("boss.n"), run: () => {
          const tpl = ["code", "life", "blank"].map((t) => ({ label: t, value: t }))
          ctl.ask("new workspace — its name", (s, [t]) => { if (s.trim()) ctl.did(data.workspaceNew(s.trim(), t as string)) }, { cycles: [{ name: "from", values: tpl, i: 0 }] })
        },
      },
      { ...bind("boss.e"), run: () => ctl.open({ kind: "card" }) },
      { ...bind("boss.S"), run: () => ctl.open({ kind: "settings" }) },
      ...(w === null ? [] : [{ ...bind("boss.d"), run: () => ctl.ask2(`close ${wsName(app)} (its threads move to another workspace)`, () => void ctl.did(data.workspaceDelete(w))) }]),
      { ...bind("boss.+"), run: ctl.hire },
      { ...bind("boss.\\"), run: () => ctl.open({ kind: "look", name: MY_LOOK }) },
      ctl.back1,
    ],
  }
}

export function workspaceCard(app: State, ctl: Ctl): Card {
  const w = app.ws
  if (!app.card || w === null) return { title: "SETTINGS", rows: [{ segs: [waiting(app, "reading…")] }], actions: [ctl.back1] }
  const c = app.card, ring = (xs: string[], x: string) => xs[(xs.indexOf(x) + 1) % xs.length]!
  const reload = () => void ctl.loadCard().then(ctl.draw)
  const rows: Row[] = [
    { segs: [dim("type  "), plain(c.type), dim("   scope  "), plain(c.scope), dim("   icon  "), plain(c.icon ?? "—")] },
    { segs: [key(`REPOS · ${c.repos.length}`)] },
    ...c.repos.map((r): Row => ({ segs: [plain(`  ${r.path}`), dim(r.remote ? `  ${r.remote}` : "")], open: () => void 0, ref: r })),
  ]
  const repo = rows[app.sel]?.ref as data.WorkspaceCard["repos"][number] | undefined
  return {
    title: `${c.name.toUpperCase()} · SETTINGS`, rows,
    actions: [
      { ...bind("card.T", `type: ${c.type} → next`), run: () => void ctl.did(data.workspaceEdit(w, { type: ring(["code", "life", "blank"], c.type) })).then(reload) },
      { ...bind("card.s", `scope: ${c.scope} → next`), run: () => void ctl.did(data.workspaceEdit(w, { scope: ring(["project", "machine"], c.scope) })).then(reload) },
      { ...bind("card.I"), run: () => ctl.ask("icon", (s) => void ctl.did(data.workspaceEdit(w, { icon: s.trim() })).then(reload), { text: c.icon ?? "" }) },
      { ...bind("card.+"), run: () => ctl.ask("add a repo — its path", (s) => { if (s.trim()) void ctl.did(data.repoAdd(w, s.trim())).then(reload) }) },
      ...(repo ? [{ ...bind("card.-", `remove ${repo.path.split("/").pop()}`), run: () => ctl.ask2(`remove ${repo.path} from ${c.name}`, () => void ctl.did(data.repoRemove(repo.id)).then(reload)) }] : []),
      ctl.back1,
    ],
  }
}

export function whimsyCard(app: State, ctl: Ctl): Card {
  const rows: Row[] = whimsyRows(app.whim).map((w) => ({
    segs: [plain(w.label.padEnd(16)), { s: w.value.padEnd(10), fg: ROLE.key }, dim(w.note ?? "")],
    open: () => { ctl.setWhim(w.next(app.whim)); ctl.draw() },
  }))
  return {
    title: `${whimsyTitle(app.whim)} · ⏎ changes the selected dial`, rows,
    actions: [{ ...bind("whimsy.0"), run: () => { ctl.setWhim(resetToPreset(app.whim)); ctl.draw() } }, ctl.back1],
  }
}

export function settingsCard(app: State, ctl: Ctl): Card {
  if (!app.settings) return { title: "THE RUNNING SYSTEM", rows: [{ segs: [waiting(app, "reading…")] }], actions: [ctl.back1] }
  const reload = () => void ctl.loadCard().then(ctl.draw)
  const show = (k: data.Knob) => (k.value === null ? "off" : k.type === "bool" ? (k.value ? "on" : "off") : String(k.value) || "—")
  const change = (k: data.Knob) => {
    if (k.type === "bool") return void ctl.did(data.settingsEdit(k.key, !k.value)).then(reload)
    const range = k.type === "int" ? ` (${k.min}–${k.max}${k.nullable ? ", empty: off" : ""})` : ""
    ctl.ask(`${k.key}${range}`, (s) => {
      const t = s.trim()
      const v = k.type === "string" ? t : t === "" && k.nullable ? null : Number(t)
      if (typeof v === "number" && !Number.isInteger(v)) return void (app.status = `${k.key} wants a whole number`)
      void ctl.did(data.settingsEdit(k.key, v)).then(reload)
    }, { text: k.value === null ? "" : String(k.value) })
  }
  const rows: Row[] = app.settings.knobs.map((k) => ({
    segs: [plain(k.key.padEnd(24)), { s: show(k).padEnd(8), fg: k.value === k.default ? ROLE.prose : ROLE.key }, dim(k.boot ? "on restart  " : "            "), dim(k.doc)],
    open: () => change(k), ref: k,
  }))
  if (app.settings.restart_pending) rows.unshift({ segs: [key("a restart is scheduled"), dim(" — it runs the moment nobody is mid-turn")] })
  return {
    title: "THE RUNNING SYSTEM · ⏎ changes the selected knob", rows,
    actions: [
      { ...bind("settings.Z"), run: () => ctl.open({ kind: "whimsy" }) },
      ...(app.settings.restart_pending ? [{ ...bind("settings.x"), run: () => void ctl.did(data.restartCancel()).then(reload) }] : []),
      ctl.back1,
    ],
  }
}
