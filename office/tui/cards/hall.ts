import { mkdirSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { SLOTS } from "../../kit/parts"
import { bringBack, candidateOf, dropPile, drawSoul, editField, hallSignature, maybe, pass, saveHall, toggleLock, type Hall } from "../../kit/hall"
import { hallRows, type RowEdit } from "../hall"
import * as data from "../data"
import { bind } from "../keys"
import { SOULS, HALL, type Row, type Card } from "../state"
import { hallCtx } from "../select"
import { dim, plain } from "../ui"
import { saveLook } from "./look"
import type { State } from "../state"
import type { Ctl } from "../ctl"

export function hallSet(app: State, h: Hall) { app.hall = h; saveHall(HALL, h); app.hallSeen = hallSignature(HALL) }

/** `e` on the lit row: cycle a vocab field in place, ask for a name, the pitch or the soul, open the look card on a slot */
export function hallEdit(app: State, ctl: Ctl, what: RowEdit) {
  const ctx = hallCtx(app), c = candidateOf(app.hall, ctx)
  const apply = (r: Hall | { error: string }) => { if ("error" in r) app.status = r.error; else hallSet(app, r); ctl.draw() }
  if ((SLOTS as readonly string[]).includes(what)) return ctl.open({ kind: "look", name: c.name, hall: true })
  if (what === "archetype" || what === "grade" || what === "specialty") {
    const opts = ctx.vocab[({ archetype: "archetypes", grade: "grades", specialty: "specialties" } as const)[what]]
    return apply(editField(app.hall, ctx, what, opts[(opts.indexOf(c[what]) + 1) % opts.length]!))
  }
  const f = what as "name" | "pitch" | "soul"
  // a name being edited is not taken by itself
  const own = { ...ctx, taken: ctx.taken.filter((n) => n !== c.name) }
  ctl.ask(f === "soul" ? `soul for ${c.name}` : `${f} for ${c.name}`, (s) => apply(editField(app.hall, own, f, s)), { text: c[f], multiline: f === "soul" })
}

export async function hallDraw(app: State, ctl: Ctl) {
  if (app.ws === null) return
  const c = candidateOf(app.hall, hallCtx(app))
  app.status = `drawing ${c.name}…`; ctl.draw()
  const r = await data.draftSoul(app.ws, c)
  if ("error" in r) app.status = r.error
  else if (candidateOf(app.hall, hallCtx(app)).name !== c.name) return ctl.draw()
  else { hallSet(app, drawSoul(app.hall, r)); app.status = `drew ${c.name}'s soul (${r.source}) — e to edit` }
  ctl.draw()
}

export async function hallHire(app: State, ctl: Ctl) {
  const ctx = hallCtx(app), c = candidateOf(app.hall, ctx)
  if (ctx.taken.includes(c.name)) { app.status = `${c.name} is already on the bench — pass, or drop it`; return ctl.draw() }
  if (app.world) app.world.hire(c)
  else {
    if (app.ws === null) return
    const said = await data.hire(app.ws, c.name, c.archetype)
    // data.hire's own success line; anything else is the refusal, and nothing is kept
    if (!said.startsWith("hired ")) { app.status = said; return ctl.draw() }
  }
  saveLook(app, c.name, c.look)
  try { mkdirSync(SOULS, { recursive: true }); writeFileSync(join(SOULS, `${c.name}.md`), c.soul, { flag: "wx" }) } catch { /* theirs already: never overwritten */ }
  app.soulsSeen = ""
  hallSet(app, pass(app.hall, { ...ctx, taken: [...ctx.taken, c.name] }))
  app.status = `hired ${c.name}`
  void ctl.refresh()
  ctl.draw()
}

export function hallCard(app: State, ctl: Ctl): Card {
  const c = candidateOf(app.hall, hallCtx(app))
  const rows: Row[] = hallRows(c, app.hall.locks).map((r) => ({
    segs: r.segs,
    open: r.lock ? () => { hallSet(app, { ...app.hall, locks: toggleLock(app.hall.locks, r.lock!.kind, r.lock!.key) }); ctl.draw() } : undefined,
  }))
  return {
    title: `HIRING HALL · ${app.hall.seed} · ${app.hall.pile.length} maybe`, rows,
    actions: [
      { ...bind("hall.left"), run: () => { hallSet(app, pass(app.hall, hallCtx(app))); ctl.draw() } },
      { ...bind("hall.up"), run: () => { hallSet(app, maybe(app.hall, hallCtx(app))); ctl.draw() } },
      { ...bind("hall.right"), run: () => void hallHire(app, ctl) },
      { ...bind("hall.space"), run: () => rows[app.sel]?.open?.() },
      { ...bind("hall.m"), run: () => ctl.open({ kind: "hall-pile" }) },
      { ...bind("hall.e"), run: () => { const w = hallRows(c, app.hall.locks)[app.sel]?.edit; if (w) hallEdit(app, ctl, w) } },
      { ...bind("hall.W"), run: () => void hallDraw(app, ctl) },
      ctl.back1,
    ],
  }
}

export function hallPileCard(app: State, ctl: Ctl): Card {
  const rows: Row[] = app.hall.pile.map((e, i) => {
    const c = candidateOf({ ...app.hall, seed: e.seed, overrides: e.overrides, locks: {} }, hallCtx(app))
    return { segs: [plain(c.name.padEnd(14)), dim(`${c.grade} ${c.archetype} · ${c.specialty} · ${e.seed}`)], ref: i, open: () => { hallSet(app, bringBack(app.hall, i)); ctl.open({ kind: "hall" }) } }
  })
  return {
    title: `MAYBE PILE · ${app.hall.pile.length}`,
    rows: rows.length ? rows : [{ segs: [dim("nobody yet — ↑ in the hall keeps a candidate here")] }],
    actions: [
      { ...bind("hall-pile.x"), run: () => { const i = rows[app.sel]?.ref; if (typeof i === "number") { hallSet(app, { ...app.hall, pile: dropPile(app.hall.pile, i) }); app.sel = Math.max(0, app.sel - 1); ctl.draw() } } },
      { ...bind("hall-pile.esc"), run: () => ctl.open({ kind: "hall" }) },
    ],
  }
}
