import { resetToPreset, whimsyRows, whimsyTitle } from "../whimsy-card"
import { soulFor } from "../../kit/souls"
import { overrideFor } from "../../kit/looks"
import { ROLE } from "../../kit/palette"
import { castSignature, saveCast, setTrait, type Cast } from "../../kit/cast"
import { CAST_FIELDS, castRows, nextTrait, rerollTrait } from "../cast"
import { rollLook } from "../../kit/sprites"
import { type Agents, type Coworker } from "../../kit/types"
import { bind } from "../keys"
import { CAST, type Mode, type Row, type Card } from "../state"
import { dim, key, plain } from "../ui"
import { pickModel, pickPersona, unseatAsk } from "./crew"
import { hallVocab } from "../select"
import { saveLook } from "./look"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function castSet(app: State, c: Cast) { app.cast = c; saveCast(CAST, c); app.castSeen = castSignature(CAST) }

export function castCard(app: State, ctl: Ctl, a: Agents, mode: Extract<Mode, { kind: "cast" }>): Card {
  const on = mode.tab
  const tab = { ...bind("cast.tab"), run: () => ctl.open({ kind: "cast", tab: on === "people" ? "office" : "people" }) }
  if (on === "office") {
    const rows: Row[] = whimsyRows(app.whim).map((w) => ({
      segs: [plain(w.label.padEnd(16)), { s: w.value.padEnd(10), fg: ROLE.key }, dim(w.note ?? "")],
      open: () => { ctl.setWhim(w.next(app.whim)); ctl.draw() },
    }))
    return { title: `THE CAST · office · ${whimsyTitle(app.whim)}`, rows, actions: [tab, { ...bind("whimsy.0"), run: () => { ctl.setWhim(resetToPreset(app.whim)); ctl.draw() } }, ctl.back1] }
  }
  const seats = a.bench.map((b) => ({ name: b.name, archetype: b.archetype, model: b.model?.model ?? null, voice: b.persona?.voice ?? null, hasSoul: !!soulFor(b.name), hasLook: !!overrideFor(b.name) }))
  const change = (b: Coworker) => {
    const f = CAST_FIELDS[app.castCol]
    if (f === "model") pickModel(app, ctl, b)
    else if (f === "voice") pickPersona(app, ctl, b)
    else if (f === "name" || f === "archetype") { app.status = `a seat's ${f} doesn't change — hire a new one from the hall (h)`; ctl.draw() }
    else if (f === "look") ctl.open({ kind: "look", name: b.name, from: mode })
    else if (f === "soul") ctl.openSoul(b.name)
    else if (f === "grade" || f === "specialty") {
      const vocab = f === "grade" ? hallVocab(app).grades : hallVocab(app).specialties
      castSet(app, setTrait(app.cast, b.name, f, nextTrait(vocab, app.cast[b.name]?.[f] ?? "unset"))); ctl.draw()
    }
  }
  const reroll = (b: Coworker) => {
    const f = CAST_FIELDS[app.castCol]
    if (f === "look") { saveLook(app, b.name, { ...(overrideFor(b.name) ?? {}), ...rollLook(`${b.name}:${app.rolls++}`) }); app.roomChanged = true; ctl.draw() }
    if (f === "grade" || f === "specialty") { castSet(app, setTrait(app.cast, b.name, f, rerollTrait(`${b.name}:${app.castRolls++}`, f, hallVocab(app)))); ctl.draw() }
  }
  const rows: Row[] = castRows(seats, app.cast).map((r, i) => ({
    segs: [plain(r.name.padEnd(14)), ...r.cells.slice(1).map((c, j) => i === app.sel && j + 1 === app.castCol ? key(`[${c.value}] `) : (c.editable ? plain : dim)(`${c.value}  `))],
    ref: a.bench[i], open: () => change(a.bench[i]!),
  }))
  const lit = rows[app.sel]?.ref as Coworker | undefined
  if (!rows.length) rows.push({ segs: [dim("nobody on the bench yet — hire from the hall (h)")] })
  const step = (d: number) => { app.castCol = (app.castCol + d + CAST_FIELDS.length) % CAST_FIELDS.length; ctl.draw() }
  return {
    title: `THE CAST · people · ${CAST_FIELDS[app.castCol]}`, rows,
    actions: [
      tab, { ...bind("cast.left"), run: () => step(-1) }, { ...bind("cast.right"), run: () => step(1) },
      { ...bind("cast.enter"), run: () => rows[app.sel]?.open?.() },
      ...(lit ? [{ ...bind("cast.y"), run: () => reroll(lit) }, { ...bind("cast.-"), run: () => unseatAsk(app, ctl, lit) }] : []),
      ctl.back1,
    ],
  }
}
