// What the whiteboard says, independent of how a room draws it: the rooms keep geometry and colour.
import { boardColumns, isManager, peopleOf, seating, stickyItems, STATE_GLYPH, type Act, type BoardCtx, type BoardItem } from "./crew"
import type { Agents, Seat } from "./types"

export type WhiteboardColumn = { name: string; count: number; items: BoardItem[] }

/** the board's columns as a room draws them: the TICKETS column holds its stickies (groups and loose tickets), while `count` is still its tickets */
export function whiteboardItems(a: Agents, ctx: BoardCtx = {}): WhiteboardColumn[] {
  return boardColumns(a, ctx).map((col, c) => ({
    name: col.name,
    count: col.items.length,
    items: c === 0 ? stickyItems(a).map((s): BoardItem => ({ act: s.act, title: s.text, who: null, stage: "", asks: false, archetype: null, high: false })) : col.items,
  }))
}

/** the ticket or thread id a line names (0: none) */
export const idOf = (act: Act): number => act.kind === "ticket" || act.kind === "epic" ? act.id : act.kind === "thread" ? act.tid : 0

/** a line's click target and tooltip */
export function hitFor(it: BoardItem): { tip: string; act: Act } {
  const head = `${it.act.kind === "column" ? "" : `#${idOf(it.act)} `}${it.title}`
  const state = it.state ? `\n${STATE_GLYPH[it.state.kind]} ${it.state.why}` : it.asks ? "\nwaiting on you" : ""
  const detail = it.stage || it.who ? `\n${it.stage}${it.who ? ` · ${it.who}` : ""}` : ""
  return { tip: `${head}${detail}${state}`, act: it.act }
}

/** who sits where, before any room's geometry: everyone, the manager, the lead and the rest in seating order */
export function seatPlan(a: Agents): { people: Seat[]; manager: Seat | undefined; lead: Seat | undefined; grunts: Seat[] } {
  const people = peopleOf(a)
  const managers = people.filter((p) => isManager(a, p)), workers = people.filter((p) => !isManager(a, p))
  return { people, manager: managers[0], ...seating(a, workers) }
}
