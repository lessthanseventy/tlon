import { rows as trophyRows, won as wonTrophies } from "../../kit/trophies"
import { needsYou, BOARD_LEGEND } from "../../kit/crew"
import { ROLE } from "../../kit/palette"
import { shirtOf } from "../../kit/sprites"
import { flagOn, type Agents, type CorkNote } from "../../kit/types"
import { WideRoom } from "../../rooms/wide"
import * as data from "../data"
import { bind, everywhere } from "../keys"
import { PLAY, PLAY_ROWS, ROOM_PLAY, WORLD_ROWS } from "../sandbox"
import { wrap } from "../editor"
import { READER_KEYS } from "../reader"
import { type Hint } from "../pane"
import { TOY_KEYS, type Mode, type Row, type Action, type Card } from "../state"
import { dim, key, paneW, pink, plain } from "../ui"
import { changed } from "../select"
import type { State } from "../state"
import type { Ctl } from "../ctl"

/** the triage card's lit row and the issue card share these: the issue verbs are the inbox's issue need's */
/** the whiteboard's marks, worded: one row per state the board draws, and what its colour is */
export function boardLegend(): Row[] {
  return [
    { segs: [key("the whiteboard's marks")] },
    ...BOARD_LEGEND.map(([mark, words]): Row => ({ segs: [plain("  "), { s: mark.padEnd(3), fg: ROLE.key, bold: true }, plain(words)] })),
    { segs: [dim("  a mark's colour is its lead's role (their shirt); hover a line for its state in words")] },
  ]
}

export function homeCard(app: State, ctl: Ctl, a: Agents): Card {
  const w = app.ws
  const waiting = a.threads.filter(needsYou)
  const actions: Action[] = [
    { ...bind("home./"), run: () => void ctl.finder() }, { ...bind("home.i"), run: ctl.inbox },
    { ...bind("home.n"), run: ctl.newThread }, { ...bind("home.N"), run: ctl.newTicket },
    { ...bind("home.c"), run: () => ctl.open({ kind: "crew" }) }, { ...bind("home.t"), run: () => ctl.open({ kind: "column", col: 0 }) },
    { ...bind("home.w"), run: () => ctl.open({ kind: "tray" }) }, { ...bind("home.!"), run: () => ctl.open({ kind: "triage" }) },
    { ...bind("home.a"), run: () => ctl.open({ kind: "calendar" }) }, { ...bind("home.o"), run: () => ctl.open({ kind: "notes" }) },
    { ...bind("home.b"), run: () => ctl.open({ kind: "memory" }) }, { ...bind("home.H"), run: () => ctl.open({ kind: "health" }) },
    ...(app.all.life?.[String(w)] ? [{ ...bind("home.L"), run: () => ctl.open({ kind: "life" }) }] : []),
    ...(flagOn(app.all, "build_mode") ? [{ ...bind("home.B"), run: () => ctl.open({ kind: "build" }) }] : []),
    { ...bind("home.f"), run: () => ctl.open({ kind: "archive" }) }, { ...bind("home.W"), run: () => ctl.open({ kind: "boss" }) },
    { ...bind("home.S"), run: () => ctl.open({ kind: "settings" }) },
    { ...bind("home.h"), run: () => ctl.open({ kind: "hall" }) },
    { ...bind("home.cast"), run: () => ctl.open({ kind: "cast", tab: "people" }) },
    { ...bind("home.P"), run: () => ctl.open({ kind: "store" }) },
    { ...bind("home.q"), run: ctl.quit },
  ]
  if (!waiting.length) return { title: "HOME", rows: [{ segs: [dim("nothing waits on you. click someone — or Nina, or Argos — a sticky or the crew board;")] }, { segs: [dim("tab walks the crew, [ ] the workspaces.")] }], actions }
  return { title: `WAITING ON YOU · ${waiting.length}`, rows: waiting.map((t) => ({ segs: [key(`#${t.id} `), plain(t.title), pink(`  ${t.prompt?.summary ?? `awaits ${t.awaiting}`}`)], open: () => ctl.openReader(t.id) })), actions }
}

export function babelCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "babel" }>): Card {
  return {
    title: "THE LIBRARY OF BABEL · a page, at random",
    tint: ROLE.inactive,
    rows: mode.page.map((l): Row => ({ segs: [/[a-z]{4,} [a-z]{3,}/.test(l.trim()) && !l.includes(",") ? { s: l, fg: ROLE.attention } : dim(l)] })),
    actions: [{ ...bind("babel.n"), run: ctl.openBabel }, ctl.back1],
  }
}

export function ideasCard(app: State, ctl: Ctl, a: Agents): Card {
  const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
  const rows: Row[] = app.ideas.map((n) => ({ segs: [who(n.author), plain(n.body)], ref: n }))
  const picked = rows[app.sel]?.ref as CorkNote | undefined, w = app.ws
  const gone = (id: number) => { app.ideas = app.ideas.filter((x) => x.id !== id); ctl.room().suggestionBox(app.ideas) }
  return {
    title: `SUGGESTION BOX · ${app.ideas.length} · the crew's ideas, yours to file or throw out`, rows: rows.length ? rows : [{ segs: [dim("the box is empty. a coworker drops an idea in it when they see one while working.")] }],
    actions: [
      ...(picked && w !== null ? [
        { ...bind("ideas.t"), run: () => void ctl.did(data.ticketFile(w, picked.body)).then(() => data.dropSuggestion(w, picked.id)).then(() => { gone(picked.id); ctl.draw() }) },
        { ...bind("ideas.d"), run: () => void data.dropSuggestion(w, picked.id).then(() => { gone(picked.id); ctl.draw() }) },
      ] : []),
      ctl.back1,
    ],
  }
}

export function banterCard(app: State, ctl: Ctl, a: Agents): Card {
  const who = (name: string) => ({ s: `${name}: `, fg: shirtOf(a.bench.find((b) => b.name === name)?.archetype) })
  const at = (ms: number) => dim(`${new Date(ms).toTimeString().slice(0, 5)}  `)
  const rows: Row[] = [...app.said].reverse().flatMap((x) => wrap(x.line, paneW() - 14 - x.who.length).map((l, n): Row => ({ segs: n ? [dim(" ".repeat(9 + x.who.length)), plain(l)] : [at(x.at), who(x.who), plain(l)] })))
  return {
    title: `BANTER · the last ${app.said.length} lines said in the room, newest first`,
    rows: rows.length ? rows : [{ segs: [dim("nobody has said anything yet. the crew talks when two of them meet.")] }],
    actions: [ctl.back1],
  }
}

export function trophiesCard(app: State, ctl: Ctl): Card {
  const rows: Row[] = trophyRows(app.trophies).map((t): Row => ({ segs: [t.won ? pink("★ ") : dim("☆ "), plain(t.name.padEnd(24)), dim(t.note)] }))
  return { title: `TROPHIES · ${wonTrophies(app.trophies).length} won · a cup on the lounge shelf for each`, rows, actions: [ctl.back1] }
}

export function arcadeCard(app: State, ctl: Ctl): Card {
  // the coworkers' best scores on the cabinets, where the room keeps them
  const r = ctl.room(), highs: Row[] = r instanceof WideRoom ? r.highScores().flatMap((h, i): Row[] => (h ? [{ segs: [key(`cabinet ${i + 1}  `), plain(`best ${h.score}`), dim(`  by ${h.name}`)] }] : [])) : []
  const rows: Row[] = GAMES.map((g): Row => (Bun.which(g.cmd) ? { segs: [plain(g.name.padEnd(16)), dim(g.what)], open: () => ctl.play(g) } : { segs: [dim(g.name.padEnd(16)), dim("not installed")] }))
  return {
    title: "ARCADE", rows: [{ segs: [plain("the office's cabinets. a game you leave with ctrl+] (to the room) waits for you; quitting it brings the room back.")] }, ...highs, ...rows],
    actions: [ctl.back1],
  }
}

export function playCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "play" }>): Card {
  const page2 = mode.page === 2; return {
    title: "PLAY", rows: [{ segs: [plain(page2 ? "pick a toy (page 2 of 2)" : "pick a toy")] }],
    actions: [...PLAY_ROWS.filter((b) => ("mode" in b) === page2 && (app.world || !WORLD_ROWS.includes(b.id))).map((b): Action => ({
      ...bind(b.id),
      run: b.id === "play.more" || b.id === "play.first" ? () => { ctl.playDo(b.id); ctl.draw() } : () => { ctl.back(); ctl.playDo(b.id); changed(app); ctl.draw() },
    })), ctl.back1],
  }
}

export function helpCard(app: State, ctl: Ctl, mode: Extract<Mode, { kind: "help" }>): Card {
  const m = mode
  const sect = (name: string, hs: Hint[]): Row[] => hs.length ? [{ segs: [key(name)] }, ...hs.map((h) => ({ segs: [plain("  "), { s: h.key.padEnd(10), fg: ROLE.key, bold: true }, plain(h.label)] }))] : []
  return {
    title: `HELP · ${m.title}`,
    actions: [{ ...bind("help.esc", `back to ${m.title.toLowerCase()}`), run: () => { app.mode = m.from; app.sel = 0; app.scroll = 0; app.snapSel = true; ctl.draw() } }],
    rows: [...sect(m.title.toLowerCase(), m.keys), ...sect("everywhere", everywhere()), ...sect("reading a thread (its card's keys work there too)", READER_KEYS), ...(app.world ? sect("the sandbox's play key (it wins over a card's)", PLAY) : TOY_KEYS ? sect("the room's play keys (a card's own key wins)", ROOM_PLAY) : []), ...boardLegend()],
  }
}

/** the arcade's games: terminal games, played wherever the machine has installed them */
export const GAMES = [
  { name: "Space Invaders", cmd: "ninvaders", what: "ninvaders" },
  { name: "Pac-Man", cmd: "myman", what: "myman" },
  { name: "Moon Buggy", cmd: "moon-buggy", what: "jump the craters" },
  { name: "Snake", cmd: "nsnake", what: "nsnake" },
  { name: "Tetris", cmd: "bastet", what: "bastet, which picks the worst block on purpose" },
  { name: "2048", cmd: "2048-in-terminal", what: "slide and merge" },
  { name: "Minesweeper", cmd: "freesweep", what: "freesweep" },
  { name: "Sudoku", cmd: "nudoku", what: "nudoku" },
  { name: "Solitaire", cmd: "ttysolitaire", what: "klondike" },
  { name: "Doom", cmd: "doom", what: "Freedoom, drawn in text" },
]
