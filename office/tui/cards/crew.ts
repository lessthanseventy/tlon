import { ledgerLines, MUG, NAMEPLATE, SHERIFF } from "../../kit/scharlach"
import { crewOf, statusGlyph, statusTone, statusWord, type SeatStatus } from "../../kit/crew"
import { soulFor } from "../../kit/souls"
import { personCard as soulCard } from "../person-card"
import { ROLE } from "../../kit/palette"
import { shirtOf } from "../../kit/sprites"
import { type Agents, type Coworker } from "../../kit/types"
import * as data from "../data"
import { bind } from "../keys"
import { badge, type Seg } from "../term"
import { arrange, CREW_SORTS, next } from "../order"
import { CREW_GROUP_MODES, type Mode, type Row, type Action, type Card } from "../state"
import { crewOn, crewsOf, inheritedModel, nextCrew, threadOf, view, wsName } from "../select"
import { cols, dim, key, plain, tabLabel } from "../ui"
import { liveActions, threadActions, threadRows } from "./thread"
import type { State } from "../state"
import type { Ctl } from "../ctl"

/** the model picker for a seat; the seat card and the cast view share it */
export function pickModel(app: State, ctl: Ctl, b: Coworker) {
  const w = app.ws, a = view(app)
  if (w === null) return
  const models = [{ label: `the archetype's (${inheritedModel(app, b.archetype)})`, value: "inherit" }, ...a.models.map((m) => ({ label: `${m.key}  ${m.thinking} · ${m.harness}`, value: m.key }))]
  ctl.find(`${b.name.toUpperCase()}'S MODEL`, models.map((m) => ({ segs: [plain(m.label)], text: m.label, run: () => { app.picker = null; void ctl.did(data.retarget(w, b.agent_id, { model: m.value })) } })))
}

/** the persona picker for a seat: make or reroll one, or edit its voice, backstory and quirks */
export function pickPersona(app: State, ctl: Ctl, b: Coworker) {
  const w = app.ws
  if (w === null) return
  const p = b.persona
  const items: { label: string; run: () => void }[] = [
    p
      ? { label: "draw a new one (reroll)", run: () => ctl.ask2(`reroll ${b.name}'s persona — the hand edits go`, () => { app.status = "drawing a new one…"; ctl.draw(); void ctl.did(data.persona(w, b.agent_id, true)) }) }
      : { label: "make one", run: () => { app.status = "drawing one…"; ctl.draw(); void ctl.did(data.persona(w, b.agent_id, false)) } },
    ...(p ? [
      { label: "edit the voice", run: () => ctl.ask(`${b.name}'s voice`, (s) => { if (s.trim()) void ctl.did(data.personaEdit(w, b.agent_id, { voice: s.trim() })) }, { text: p.voice }) },
      { label: "edit the backstory", run: () => ctl.ask(`${b.name}'s backstory`, (s) => { if (s.trim()) void ctl.did(data.personaEdit(w, b.agent_id, { backstory: s.trim() })) }, { text: p.backstory }) },
      ...(["desk_object", "hobby", "catchphrase", "pet_peeve"] as const).map((k) => ({ label: `edit ${k.replace("_", " ")}`, run: () => ctl.ask(`${b.name}'s ${k.replace("_", " ")}`, (s) => { if (s.trim()) void ctl.did(data.personaEdit(w, b.agent_id, { quirks: { [k]: s.trim() } })) }, { text: p.quirks[k] }) })),
    ] : []),
  ]
  ctl.find(`${b.name.toUpperCase()}'S PERSONA`, items.map((i) => ({ segs: [plain(i.label)], text: i.label, run: () => { app.picker = null; i.run() } })))
}

/** confirm, then let a seat go from this workspace (the agent itself stays) */
export function unseatAsk(app: State, ctl: Ctl, b: Coworker) {
  ctl.ask2(`let ${b.name} go from ${wsName(app)} (the agent itself stays)`, () => ctl.did(data.unseat(b.seat_id, b.name)))
}

/** the verbs on a seated coworker: their model, ask/allow, a clean slate, letting them go */
export function seatActions(app: State, ctl: Ctl, b: Coworker | undefined): Action[] {
  const w = app.ws
  if (!b || w === null) return []
  return [
    { ...bind("seat.M"), run: () => pickModel(app, ctl, b) },
    { ...bind("seat.y", b.ask === "allow" ? "ask before acting" : "allow without asking"), run: () => void ctl.did(data.retarget(w, b.agent_id, { ask: b.ask === "allow" ? "ask" : "allow" })) },
    { ...bind("seat.E"), run: () => pickPersona(app, ctl, b) },
    { ...bind("seat.C"), run: () => ctl.ask2(`clear ${b.name}'s context — their session ends, they start fresh when next needed`, () => ctl.did(data.clearContext(w, b.agent_id, b.name))) },
    { ...bind("seat.-"), run: () => unseatAsk(app, ctl, b) },
  ]
}

export function crewCard(app: State, ctl: Ctl, a: Agents): Card {
  // tabs: each crew, then everyone; the crew on has the live status
  const seats = (app.all.shifts ?? []).filter((x) => x.workspace_id === app.ws)
  const crews = crewsOf(app, app.ws), tabsOf = [...crews, "all"], on = crewOn(app), other = nextCrew(app)
  if (!tabsOf.includes(app.crewTab)) app.crewTab = "all"
  const live = crewOf(a)
  const inTab = (name: string) => app.crewTab === "all" || seats.find((x) => x.name === name)?.crew === app.crewTab
  const crew = [...live, ...seats.filter((x) => !live.some((c) => c.name === x.name)).map((x) => ({ name: x.name, archetype: x.archetype, status: "off" as SeatStatus, thread: null, title: "", manager: false, lead: false }))].filter((c) => inTab(c.name))
  const shiftOf = (name: string) => seats.find((x) => x.name === name)?.crew
  const tabs: Seg[] = tabsOf.flatMap((t) => [t === app.crewTab ? { s: ` ${tabLabel(t)} `, fg: ROLE.ground, bg: ROLE.key, bold: true } : dim(` ${tabLabel(t)} `), plain(" ")])
  const paused = app.all.pause === "pencils_down" || app.all.pause === "lights_out"
  const rows: Row[] = [{ segs: [...tabs, dim(crews.length ? `   the ${on} crew is on` : "   no crews yet: c puts a seat on one"),
    ...(paused ? badge({ s: app.all.pause === "lights_out" ? "  ◼ lights out " : "  ✎ pencils down ", fg: ROLE.ground, bg: ROLE.attention, bold: true }) : [dim("   at work")])] }]
  for (const g of arrange(crew as any, app.crewSort.cmp, app.crewGroup)) {
    if (g.label !== null) rows.push({ segs: [key(`${g.label} · ${g.items.length}`)] })
    for (const c of g.items as any[]) {
      const b = a.bench.find((x) => x.name === c.name), arch = a.archetypes.find((x) => x.name === c.archetype)
      const model = b?.model ? b.model.model : arch?.model?.split("/").pop() ?? ""
      const off = c.status === "off", shift = shiftOf(c.name)
      rows.push({
        segs: [{ s: `${statusGlyph(c.status)} `, fg: statusTone(c.status) },
          { s: c.name.padEnd(10), fg: off ? ROLE.inactive : shirtOf(c.archetype) }, dim(`${c.manager ? "manager" : c.archetype ?? "?"}${c.lead ? " · lead" : ""}`.padEnd(18)), key(model.padEnd(16)), plain(" "),
          dim((shift === "all" || !shift ? "every crew" : shift).padEnd(12)),
          dim(off && !live.some((l) => l.name === c.name) ? "off shift" : c.thread !== null ? `#${c.thread} ${c.title}` : "on the bench")],
        open: () => ctl.open({ kind: "person", name: c.name }), ref: c.name,
      })
    }
  }
  const chosen = a.bench.find((x) => x.name === rows[app.sel]?.ref), seat = seats.find((x) => x.name === rows[app.sel]?.ref)
  const seatTo = seat ? next(tabsOf, seat.crew) : "all"
  const newCrew = () => { if (seat) ctl.ask(`put ${seat.name} on a new crew — its name (lowercase, - and _)`, (s) => { if (s.trim()) void ctl.did(data.seatShift(seat.seat_id, seat.name, s.trim())) }) }
  return {
    title: `CREW · ${crew.length} · ${tabLabel(app.crewTab)} · by ${app.crewGroup ? `${app.crewGroup.name}, ` : ""}${app.crewSort.name}`,
    rows,
    actions: [{ ...bind("crew.v", `tab: ${tabLabel(next(tabsOf, app.crewTab))}`), run: () => { app.crewTab = next(tabsOf, app.crewTab); app.sel = 0; ctl.draw() } },
      ...(seat ? [{ ...bind("crew.c", `${seat.name} on ${seatTo === "all" ? "every crew" : seatTo}`), run: () => void ctl.did(data.seatShift(seat.seat_id, seat.name, seatTo)) }, { ...bind("crew.n"), run: newCrew }] : []),
      ...(other ? [{ ...bind("crew.S", `put the ${other} crew on`), run: () => { if (app.ws !== null) void ctl.did(data.shiftSwitch(app.ws, other)) } }] : []),
      { ...bind("crew.+"), run: ctl.hire },
      paused ? { ...bind("crew.P.paused"), run: () => void ctl.did(data.pause("back_to_work")) }
        : { ...bind("crew.P.running"), run: () => void ctl.did(data.pause("pencils_down")) },
      ...(app.all.pause !== "lights_out" ? [{ ...bind("crew.L"), run: () => ctl.ask2("lights out — pause verify and landing, interrupt every pane", () => void ctl.did(data.pause("lights_out"))) }] : []),
      { ...bind("crew.s", `sort: ${app.crewSort.name} → ${next(CREW_SORTS, app.crewSort).name}`), run: () => ctl.resort(() => { app.crewSort = next(CREW_SORTS, app.crewSort) }) },
      { ...bind("crew.g", `group: ${app.crewGroup?.name ?? "none"} → ${next(CREW_GROUP_MODES, app.crewGroup)?.name ?? "none"}`), run: () => ctl.resort(() => { app.crewGroup = next(CREW_GROUP_MODES, app.crewGroup) }) },
      ...seatActions(app, ctl, chosen), ctl.back1],
  }
}

export function personCard(app: State, ctl: Ctl, a: Agents, mode: Extract<Mode, { kind: "person" }>): Card {
  const name = mode.name
  const c = crewOf(a).find((x) => x.name === name), b = a.bench.find((x) => x.name === name)
  if (!c) return { title: name.toUpperCase(), rows: [{ segs: [dim("not in this office any more")] }], actions: [ctl.back1] }
  const model = b?.model ? `${b.model.provider}/${b.model.model}` : `${inheritedModel(app, c.archetype)} (archetype's)`
  const where = `${statusGlyph(c.status)} ${statusWord(c.status)}`
  // a pill for where they are, and what they're at mid-turn (the thought bubble's kind)
  const doing = a.roster.find((r) => r.agent === name && r.thinking)?.doing
  const pill = statusTone(c.status)
  const head: Row = {
    segs: [{ s: ` ${c.name} `, fg: ROLE.ground, bg: shirtOf(c.archetype), bold: true }, plain(" "), { s: ` ${where}${doing ? ` · ${doing}` : ""} `, fg: ROLE.ground, bg: pill },
      dim(`  ${c.manager ? "manager" : c.archetype ?? ""}${c.lead ? " · lead" : ""} · ${model} · ${b?.ask ?? "ask (archetype's)"}`)],
  }
  const soul = soulFor(name)
  const cardRows: Row[] = soulCard(soul, b?.persona, Math.max(20, cols() - 40), app.cardOpen).map((l) => ({ segs: [l.tone === "key" ? key(l.text) : l.tone === "plain" ? plain(l.text) : dim(l.text)] }))
  const rows: Row[] = [...(c.thread === null ? [head, { segs: [dim("on the bench")] }] : [head, ...threadRows(app, ctl, threadOf(app, c.thread), c.thread, 1)]), ...cardRows]
  // Scharlach's desk dressing: the nameplate (tertius never agreed to the second part), the mug
  // he bought himself, and the demerit ledger he keeps on the rest of the office
  if (name === SHERIFF && app.cardOpen) {
    rows.push({ segs: [dim("nameplate: "), plain(NAMEPLATE)] }, { segs: [dim("mug: "), plain(MUG)] }, ...ledgerLines(app.ledger, a.bench).map((l) => ({ segs: [dim(l)] })))
  }
  return { title: name.toUpperCase(), rows, tint: shirtOf(c.archetype), actions: [{ ...bind("person.m"), run: () => ctl.talk(name) }, { ...bind("person.v"), run: () => ctl.openConversation(name) }, ...(c.thread === null ? [] : [{ ...bind("person.w", `read #${c.thread}`), run: () => ctl.openReader(c.thread!) }, ...liveActions(app, ctl, c.thread), ...threadActions(app, ctl, c.thread).filter((x) => x.key !== "v")]), ...seatActions(app, ctl, b), { ...bind("person.l"), run: () => ctl.open({ kind: "look", name }) }, { ...bind("person.space"), run: () => { app.cardOpen = !app.cardOpen; app.scroll = Infinity; ctl.draw() } }, ctl.back1] }
}
