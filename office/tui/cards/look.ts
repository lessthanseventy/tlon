import { readFileSync } from "node:fs"
import { baseLook, overrideFor, type LookOverride } from "../../kit/looks"
import { ROLE } from "../../kit/palette"
import { dialsOf, nextDial, nextPart, PARTS, SLOTS } from "../../kit/parts"
import { candidateOf, setLook } from "../../kit/hall"
import { lookHint } from "../hall"
import { ACCESSORY, BODIES, HAIR_STYLES, HAIR_ROLES, lookOf, rollLook, OUTFIT, paints, shirtOf, SKIN_ROLES, type Accessory, type Look, type Outfit } from "../../kit/sprites"
import { bind, LEGEND_CHARS, type KeyId } from "../keys"
import { type Seg } from "../term"
import { LOOKS, writeState, type Mode, type Row, type Card } from "../state"
import { hallCtx } from "../select"
import { cycleOpt, cycleVal, dim, keyName, plain } from "../ui"
import { hallSet } from "./hall"
import type { State } from "../state"
import type { Ctl } from "../ctl"

/** read-merge-write one agent's entry into looks.json, same shape as cli.ts's importer */
export function saveLook(app: State, name: string, draft: LookOverride) {
  let all: Record<string, LookOverride> = {}
  try { all = JSON.parse(readFileSync(LOOKS, "utf8")) } catch { /* no file yet */ }
  all[name] = draft
  writeState(LOOKS, JSON.stringify(all, null, 2))
  app.looksSeen = "" // our own write: make the next poll re-read it instead of treating it as already seen
}

export const blankBuf = () => Array.from({ length: 22 }, () => ".".repeat(12))

export function lookCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "look" }>): Card {
  const m = mode, name = m.name
  const draft = (app.lookDraft ??= m.hall ? structuredClone(candidateOf(app.hall, hallCtx(app)).look) : { ...baseLook(name), ...overrideFor(name) })
  const field = (label: string, value: string, cycle: () => void): Row => ({ segs: [dim(label.padEnd(12)), plain(value)], open: () => { cycle(); ctl.draw() } })
  const rows: Row[] = [
    { segs: [dim(lookHint(!!m.hall))] },
    field("hair", draft.hair ?? "", () => { draft.hair = cycleVal(HAIR_STYLES, draft.hair!) }),
    field("hair colour", draft.hairRole ?? "", () => { draft.hairRole = cycleVal(HAIR_ROLES, draft.hairRole!) }),
    field("skin", draft.skinRole ?? "default", () => { draft.skinRole = cycleOpt(SKIN_ROLES, draft.skinRole) }),
    field("outfit", draft.outfit ?? "none", () => { draft.outfit = cycleOpt(Object.keys(OUTFIT) as Outfit[], draft.outfit) }),
    field("accessory", draft.accessory ?? "none", () => { draft.accessory = cycleOpt(Object.keys(ACCESSORY) as Accessory[], draft.accessory) }),
    field("build", draft.body ?? "average", () => { draft.body = cycleVal(BODIES, draft.body ?? "average") }),
    ...SLOTS.flatMap((slot) => {
      const spec = draft.parts?.[slot], p = spec ? PARTS[spec.id] : undefined
      return [
        field(slot, spec?.id ?? "none", () => {
          const next = nextPart(slot, spec), parts = { ...draft.parts }
          if (next) parts[slot] = next; else delete parts[slot]
          draft.parts = parts
        }),
        ...Object.keys(p?.dials ?? {}).map((dial) => field(`  ${dial}`, String(dialsOf(p!, spec!.dials)[dial]), () => { draft.parts = { ...draft.parts, [slot]: nextDial(spec!, dial) } })),
      ]
    }),
  ]
  return {
    title: `LOOK · ${name.toUpperCase()}`, rows,
    actions: [
      // ⏎ is the lit row (it cycles a field); save has its own key. A hall candidate has no looks.json entry until hired: its draft goes into hall.json
      { ...bind("look.s"), run: () => { if (m.hall) hallSet(app, setLook(app.hall, draft as Look)); else { saveLook(app, name, draft); app.roomChanged = true } app.lookDraft = null; ctl.back(); ctl.draw() } },
      { ...bind("look.r"), run: () => { Object.assign(draft, rollLook(`${name}:${app.rolls++}`)); ctl.draw() } },
      { ...bind("look.e"), run: () => {
        app.editBuf = { front: draft.custom?.front ? [...draft.custom.front] : blankBuf(), side: draft.custom?.side ? [...draft.custom.side] : blankBuf(), back: draft.custom?.back ? [...draft.custom.back] : blankBuf() }
        app.editEntry = { front: [...app.editBuf.front], side: [...app.editBuf.side], back: [...app.editBuf.back] }
        app.editCursor = { x: 0, y: 0 }; app.editScroll = 0
        app.mode = { kind: "look-editor", name, view: "front", from: m.from, hall: m.hall }; app.sel = 0; app.snapSel = true; ctl.draw()
      } },
      ctl.back1,
    ],
  }
}

export function lookEditorCard(app: State, mode: Extract<Mode, { kind: "look-editor" }>): Card {
  const { name, view } = mode
  if (!app.editBuf) { app.editBuf = { front: blankBuf(), side: blankBuf(), back: blankBuf() } }
  const draft = (app.lookDraft ?? { ...lookOf(name), ...overrideFor(name) }) as Look
  const paint = paints(shirtOf(null), draft)
  const WIN = 11
  if (app.editCursor.y < app.editScroll + 1) app.editScroll = Math.max(0, app.editCursor.y - 1)
  else if (app.editCursor.y > app.editScroll + WIN - 2) app.editScroll = Math.min(22 - WIN, app.editCursor.y - (WIN - 2))
  const legend: Seg[] = LEGEND_CHARS.flatMap((ch) => [{ s: ch, fg: paint[ch] ?? ROLE.inactive }, plain(" ")])
  const rows: Row[] = [{ segs: legend }]
  const buf = app.editBuf[view]!
  for (let y = app.editScroll; y < Math.min(22, app.editScroll + WIN); y++) {
    const r = buf[y]!, segs: Seg[] = []
    for (let x = 0; x < 12; x++) {
      const ch = r[x]!, color = ch === "." ? ROLE.inactive : (paint[ch] ?? ROLE.inactive), atCursor = y === app.editCursor.y && x === app.editCursor.x
      segs.push(atCursor ? { s: "█", fg: ROLE.ground, bg: color } : { s: ch === "." ? "·" : "█", fg: color })
    }
    rows.push({ segs })
  }
  const hint = (id: KeyId, label: string) => { const k = bind(id, label).key.split(" "); return k.length > 3 ? label : `${k.map(keyName).join("/")} ${label}` }
  rows.push({ segs: [dim([hint("lookedit.view", `view (${view})`), hint("lookedit.mirror", `mirror (${app.editMirror ? "on" : "off"})`), hint("lookedit.paint", "letter paints"), hint("lookedit.clear", "clears"), hint("lookedit.save", "save"), hint("lookedit.discard", "discard")].join(" · "))] })
  return { title: `DRAW · ${name.toUpperCase()}`, rows, actions: [] }
}
