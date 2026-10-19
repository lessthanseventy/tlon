// Every key the office TUI answers to, in one table. A card's action rows, the foot, the help card
// and the sandbox's play line are all drawn from it (`bind`, `hints`), and test/keys.test.ts reads it
// to find collisions — so a hint and the key that handles it cannot drift apart. What a key does
// stays with its handler in main.ts; here is only which key, what it is called, and where it applies.
export type Scope = "global" | "reader" | "sandbox-play" | `card:${string}`
export type Binding = {
  id: string
  scope: Scope
  /** space-separated when several keys do the one thing (`r i enter`) */
  key: string
  label: string
  /** when it applies, for a key that means something else on the same card under another condition */
  mode?: string
  /** handled, but not listed in the foot or the help card's "everywhere" */
  quiet?: boolean
}

export const KEYS = [
  // global: the foot's hints, the help card's "everywhere"
  { id: "global.find", scope: "global", key: "/", label: "find" },
  { id: "global.talk", scope: "global", key: "'", label: "talk to the office" },
  { id: "global.inbox", scope: "global", key: "i", label: "inbox" },
  { id: "global.crew", scope: "global", key: "tab", label: "crew" },
  { id: "global.workspace", scope: "global", key: "[ ]", label: "workspace" },
  { id: "global.help", scope: "global", key: "?", label: "help" },
  { id: "global.back", scope: "global", key: "esc", label: "back" },
  { id: "global.lobby", scope: "global", key: "ctrl+]", label: "lobby" },
  { id: "global.quit", scope: "global", key: "q", label: "quit" },
  // global, handled in onKey's switch but not hinted
  { id: "global.R", scope: "global", key: "R", label: "reload the TUI (when it is out of date)", mode: "when the server has a newer office", quiet: true },
  { id: "global.p", scope: "global", key: "p", label: "pat Nina", quiet: true },
  { id: "global.U", scope: "global", key: "U", label: "Uqbar's volume", quiet: true },
  { id: "global.centre", scope: "global", key: ".", label: "centre the room", quiet: true },
  { id: "global.need", scope: "global", key: ",", label: "to the first thing waiting", quiet: true },
  // card:need
  { id: "need.A.gate", scope: "card:need", key: "A", label: "approve", mode: "gate" },
  { id: "need.u.ask", scope: "card:need", key: "u", label: "hand it to Uqbar (decides and acts as you)", mode: "ask" },
  { id: "need.1.seats", scope: "card:need", key: "1", label: "raise the cap to …", mode: "seats" },
  { id: "need.R.job_failed", scope: "card:need", key: "R", label: "run it again", mode: "job_failed" },
  { id: "need.d.job_failed", scope: "card:need", key: "d", label: "dismiss", mode: "job_failed" },
  { id: "need.r.question", scope: "card:need", key: "r", label: "reply", mode: "question" },
  { id: "need.r.stalled", scope: "card:need", key: "r", label: "tell the lead what to do (wakes them)", mode: "stalled" },
  { id: "need.V.verify_failed", scope: "card:need", key: "V", label: "run verify again", mode: "verify_failed" },
  { id: "need.R.publish_failed", scope: "card:need", key: "R", label: "republish (push, open its PR)", mode: "publish_failed" },
  { id: "need.R.release_failed", scope: "card:need", key: "R", label: "retry the cut", mode: "release_failed" },
  { id: "need.b.pr_blocked", scope: "card:need", key: "b", label: "rebase it (back in the merge queue)", mode: "pr_blocked" },
  { id: "need.L.pr_blocked", scope: "card:need", key: "L", label: "close and reland (back to build)", mode: "pr_blocked" },
  { id: "need.v.pr_blocked", scope: "card:need", key: "v", label: "show me: the thread…", mode: "pr_blocked" },
  { id: "need.d.rollout", scope: "card:need", key: "d", label: "done", mode: "rollout" },
  { id: "need.X.stranded", scope: "card:need", key: "X", label: "take the checkout down (branch kept)", mode: "stranded" },
  { id: "need.g.issue", scope: "card:need", key: "g", label: "get it fixed (a ticket, routed)", mode: "issue" },
  { id: "need.x.issue", scope: "card:need", key: "x", label: "resolve…", mode: "issue" },
  { id: "need.d.publish_failed", scope: "card:need", key: "d", label: "opened by hand (the command is above): its PR's url…", mode: "publish_failed" },
  { id: "need.h.no_seat", scope: "card:need", key: "h", label: "hire a …", mode: "no_seat" },
  { id: "need.o.no_seat", scope: "card:need", key: "o", label: "hand it to…", mode: "no_seat" },
  { id: "need.P.quota", scope: "card:need", key: "P", label: "pencils down", mode: "quota" },
  { id: "need.d.quota", scope: "card:need", key: "d", label: "wait for the reset (put away until it clears)", mode: "quota" },
  { id: "need.d.decide", scope: "card:need", key: "d", label: "put away", mode: "decide-level, ask or stalled" },
  { id: "need.v", scope: "card:need", key: "v", label: "read the thread" },
  { id: "need.t", scope: "card:need", key: "t", label: "look over their shoulder" },
  // card:thread
  { id: "thread.v", scope: "card:thread", key: "v", label: "read it all" },
  { id: "thread.r", scope: "card:thread", key: "r", label: "reply" },
  { id: "thread.u", scope: "card:thread", key: "u", label: "hand to Uqbar" },
  { id: "thread.A", scope: "card:thread", key: "A", label: "approve: …" },
  { id: "thread.>", scope: "card:thread", key: ">", label: "advance the workline" },
  { id: "thread.S", scope: "card:thread", key: "S", label: "raise the cap (settings)" },
  { id: "thread.t", scope: "card:thread", key: "t", label: "look over their shoulder" },
  { id: "thread.g", scope: "card:thread", key: "g", label: "git (lazygit)" },
  { id: "thread.d", scope: "card:thread", key: "d", label: "read its docs (spec, plan…)" },
  { id: "thread.R", scope: "card:thread", key: "R", label: "review its branch" },
  { id: "thread.h", scope: "card:thread", key: "h", label: "hand off to…" },
  { id: "thread.P", scope: "card:thread", key: "P", label: "move to project…" },
  { id: "thread.x", scope: "card:thread", key: "x", label: "close as done" },
  { id: "thread.D", scope: "card:thread", key: "D", label: "delete for good" },
  // card:seat
  { id: "seat.M", scope: "card:seat", key: "M", label: "model…" },
  { id: "seat.y", scope: "card:seat", key: "y", label: "ask before acting / allow without asking" },
  { id: "seat.E", scope: "card:seat", key: "E", label: "persona…" },
  { id: "seat.C", scope: "card:seat", key: "C", label: "clear context (fresh next time)" },
  { id: "seat.-", scope: "card:seat", key: "-", label: "let go" },
  // card:live
  { id: "live.enter", scope: "card:live", key: "enter", label: "step into their session" },
  { id: "live.c", scope: "card:live", key: "c", label: "their activity / the conversation" },
  // card:back
  { id: "back.esc", scope: "card:back", key: "esc", label: "back" },
  // card:home
  { id: "home./", scope: "card:home", key: "/", label: "find anything" },
  { id: "home.i", scope: "card:home", key: "i", label: "inbox — everywhere" },
  { id: "home.n", scope: "card:home", key: "n", label: "new thread" },
  { id: "home.N", scope: "card:home", key: "N", label: "new ticket" },
  { id: "home.c", scope: "card:home", key: "c", label: "crew" },
  { id: "home.t", scope: "card:home", key: "t", label: "tickets & worklines" },
  { id: "home.w", scope: "card:home", key: "w", label: "in-tray" },
  { id: "home.!", scope: "card:home", key: "!", label: "triage" },
  { id: "home.a", scope: "card:home", key: "a", label: "calendar" },
  { id: "home.o", scope: "card:home", key: "o", label: "notes" },
  { id: "home.b", scope: "card:home", key: "b", label: "memory" },
  { id: "home.H", scope: "card:home", key: "H", label: "the rack (health)" },
  { id: "home.L", scope: "card:home", key: "L", label: "life" },
  { id: "home.D", scope: "card:home", key: "D", label: "the dump" },
  { id: "home.B", scope: "card:home", key: "B", label: "build mode" },
  { id: "home.f", scope: "card:home", key: "f", label: "filing cabinet" },
  { id: "home.W", scope: "card:home", key: "W", label: "workspaces" },
  { id: "home.S", scope: "card:home", key: "S", label: "settings (the running system)" },
  { id: "home.h", scope: "card:home", key: "h", label: "the hiring hall" },
  { id: "home.P", scope: "card:home", key: "P", label: "the pet store" },
  { id: "home.q", scope: "card:home", key: "q", label: "quit" },
  // card:crew
  { id: "crew.v", scope: "card:crew", key: "v", label: "tab: …" },
  { id: "crew.c", scope: "card:crew", key: "c", label: "… on …" },
  { id: "crew.n", scope: "card:crew", key: "n", label: "a new crew…" },
  { id: "crew.S", scope: "card:crew", key: "S", label: "put the … crew on" },
  { id: "crew.+", scope: "card:crew", key: "+", label: "hire" },
  { id: "crew.P.paused", scope: "card:crew", key: "P", label: "back to work", mode: "paused" },
  { id: "crew.P.running", scope: "card:crew", key: "P", label: "pencils down: nothing new, all stop after their turn", mode: "running" },
  { id: "crew.L", scope: "card:crew", key: "L", label: "lights out…" },
  { id: "crew.s", scope: "card:crew", key: "s", label: "sort: … → …" },
  { id: "crew.g", scope: "card:crew", key: "g", label: "group: … → …" },
  // card:person
  { id: "person.m", scope: "card:person", key: "m", label: "talk" },
  { id: "person.v", scope: "card:person", key: "v", label: "the conversation" },
  { id: "person.w", scope: "card:person", key: "w", label: "read #…" },
  { id: "person.l", scope: "card:person", key: "l", label: "look" },
  // card:column
  { id: "column.n", scope: "card:column", key: "n", label: "new ticket" },
  { id: "column.s", scope: "card:column", key: "s", label: "sort: … → …" },
  { id: "column.right", scope: "card:column", key: "right", label: "next column (← →)" },
  { id: "column.K", scope: "card:column", key: "K", label: "move up" },
  { id: "column.J", scope: "card:column", key: "J", label: "move down" },
  // card:ticket
  { id: "ticket.S", scope: "card:ticket", key: "S", label: "start it with the lead" },
  { id: "ticket.s", scope: "card:ticket", key: "s", label: "send to the manager to staff" },
  { id: "ticket.e", scope: "card:ticket", key: "e", label: "edit the title" },
  { id: "ticket.b", scope: "card:ticket", key: "b", label: "blocked by…" },
  { id: "ticket.u", scope: "card:ticket", key: "u", label: "unblock" },
  { id: "ticket.K", scope: "card:ticket", key: "K", label: "move up" },
  { id: "ticket.J", scope: "card:ticket", key: "J", label: "move down" },
  { id: "ticket.d", scope: "card:ticket", key: "d", label: "delete" },
  // card:calendar
  { id: "calendar.n", scope: "card:calendar", key: "n", label: "schedule something" },
  { id: "calendar.e", scope: "card:calendar", key: "e", label: "edit it" },
  { id: "calendar.space", scope: "card:calendar", key: "space", label: "pause it / resume it" },
  { id: "calendar.r", scope: "card:calendar", key: "r", label: "run it now" },
  { id: "calendar.d", scope: "card:calendar", key: "d", label: "delete it" },
  // card:life
  { id: "life.D", scope: "card:life", key: "D", label: "the dump" },
  { id: "life.E", scope: "card:life", key: "E", label: "earlier pages" },
  { id: "life.r", scope: "card:life", key: "r", label: "new routine" },
  { id: "life.Q", scope: "card:life", key: "Q", label: "new quest" },
  // card:pages
  { id: "pages.esc", scope: "card:pages", key: "esc", label: "life" },
  { id: "pages.enter", scope: "card:pages", key: "enter", label: "read it" },
  { id: "pages.R", scope: "card:pages", key: "R", label: "put it back" },
  // card:runs
  { id: "runs.r", scope: "card:runs", key: "r", label: "run it now" },
  { id: "runs.esc", scope: "card:runs", key: "esc", label: "the calendar" },
  // card:run
  { id: "run.esc", scope: "card:run", key: "esc", label: "the runs" },
  { id: "run.t", scope: "card:run", key: "t", label: "read its thread" },
  // card:notes
  { id: "notes.n", scope: "card:notes", key: "n", label: "pin a note" },
  // card:tray
  { id: "tray.s", scope: "card:tray", key: "s", label: "sort: … → …" },
  // card:memory
  { id: "memory.a", scope: "card:memory", key: "a", label: "approve the habit" },
  { id: "memory.r", scope: "card:memory", key: "r", label: "reject the habit" },
  { id: "memory.d", scope: "card:memory", key: "d", label: "forget the fact" },
  // card:build
  { id: "build.up", scope: "card:build", key: "up", label: "move" },
  { id: "build.down", scope: "card:build", key: "down", label: "move" },
  { id: "build.left", scope: "card:build", key: "left", label: "move" },
  { id: "build.right", scope: "card:build", key: "right", label: "move" },
  { id: "build.enter", scope: "card:build", key: "enter", label: "drop / pick up" },
  { id: "build.n", scope: "card:build", key: "n", label: "new tile (cycles the kind)" },
  { id: "build.x", scope: "card:build", key: "x", label: "remove" },
  { id: "build.r", scope: "card:build", key: "r", label: "rotate" },
  { id: "build.u", scope: "card:build", key: "u", label: "undo" },
  { id: "build.esc", scope: "card:build", key: "esc", label: "leave" },
  // card:boss
  { id: "boss.n", scope: "card:boss", key: "n", label: "new workspace" },
  { id: "boss.e", scope: "card:boss", key: "e", label: "this one's settings" },
  { id: "boss.S", scope: "card:boss", key: "S", label: "the running system" },
  { id: "boss.d", scope: "card:boss", key: "d", label: "close this one" },
  { id: "boss.+", scope: "card:boss", key: "+", label: "hire" },
  // card:card
  { id: "card.T", scope: "card:card", key: "T", label: "type: … → next" },
  { id: "card.s", scope: "card:card", key: "s", label: "scope: … → next" },
  { id: "card.I", scope: "card:card", key: "I", label: "icon" },
  { id: "card.+", scope: "card:card", key: "+", label: "add a repo" },
  { id: "card.-", scope: "card:card", key: "-", label: "remove …" },
  // card:review
  { id: "review.a", scope: "card:review", key: "a", label: "note this line" },
  { id: "review.A", scope: "card:review", key: "A", label: "note the whole file" },
  { id: "review.x", scope: "card:review", key: "x", label: "drop its note" },
  { id: "review.n", scope: "card:review", key: "n", label: "next hunk" },
  { id: "review.p", scope: "card:review", key: "p", label: "previous hunk" },
  { id: "review.N", scope: "card:review", key: "N", label: "next file" },
  { id: "review.P", scope: "card:review", key: "P", label: "previous file" },
  { id: "review.s", scope: "card:review", key: "s", label: "submit…" },
  // card:whimsy
  { id: "whimsy.0", scope: "card:whimsy", key: "0", label: "back to the preset's own dials" },
  // card:settings
  { id: "settings.Z", scope: "card:settings", key: "Z", label: "the wackiness dial" },
  { id: "settings.R", scope: "card:settings", key: "R", label: "restart the server (waits for quiet)" },
  { id: "settings.x", scope: "card:settings", key: "x", label: "cancel the scheduled restart" },
  // card:needs
  { id: "needs.f", scope: "card:needs", key: "f", label: "one at a time" },
  // card:babel
  { id: "babel.n", scope: "card:babel", key: "n", label: "another page" },
  // card:entry
  { id: "entry.m", scope: "card:entry", key: "m", label: "ask Uqbar…" },
  { id: "entry.t", scope: "card:entry", key: "t", label: "look over Uqbar's shoulder" },
  { id: "entry.v", scope: "card:entry", key: "v", label: "read the study" },
  // card:decide
  { id: "decide.n", scope: "card:decide", key: "n", label: "next" },
  { id: "decide.p", scope: "card:decide", key: "p", label: "previous" },
  { id: "decide.l", scope: "card:decide", key: "l", label: "the whole list" },
  // card:ideas
  { id: "ideas.t", scope: "card:ideas", key: "t", label: "file it as a ticket" },
  { id: "ideas.d", scope: "card:ideas", key: "d", label: "throw it out" },
  // card:pet
  { id: "pet.S.cat", scope: "card:pet", key: "S", label: "save her temperament", mode: "cat" },
  { id: "pet.p.cat", scope: "card:pet", key: "p", label: "pat her", mode: "cat" },
  { id: "pet.z.cat", scope: "card:pet", key: "z", label: "the zoomies", mode: "cat" },
  { id: "pet.y.cat", scope: "card:pet", key: "y", label: "play with the yarn", mode: "cat" },
  { id: "pet.c.cat", scope: "card:pet", key: "c", label: "come to my desk", mode: "cat" },
  { id: "pet.s.cat", scope: "card:pet", key: "s", label: "go have a nap", mode: "cat" },
  { id: "pet.b.cat", scope: "card:pet", key: "b", label: "a drink from the tub", mode: "cat" },
  { id: "pet.u.cat", scope: "card:pet", key: "u", label: "curl up in the tub", mode: "cat" },
  { id: "pet.g.cat", scope: "card:pet", key: "g", label: "go cheer someone on", mode: "cat" },
  { id: "pet.l.cat", scope: "card:pet", key: "l", label: "Nina carries a letter", mode: "cat" },
  { id: "pet.p.dog", scope: "card:pet", key: "p", label: "pat him", mode: "dog" },
  { id: "pet.w.dog", scope: "card:pet", key: "w", label: "go for a walk", mode: "dog" },
  { id: "pet.o.dog", scope: "card:pet", key: "o", label: "come to my office", mode: "dog" },
  { id: "pet.s.dog", scope: "card:pet", key: "s", label: "sit", mode: "dog" },
  { id: "pet.b.dog", scope: "card:pet", key: "b", label: "bed", mode: "dog" },
  { id: "pet.g.dog", scope: "card:pet", key: "g", label: "go cheer someone on", mode: "dog" },
  // card:look
  { id: "look.s", scope: "card:look", key: "s", label: "save" },
  { id: "look.r", scope: "card:look", key: "r", label: "roll" },
  { id: "look.e", scope: "card:look", key: "e", label: "draw a custom look" },
  // card:hall
  { id: "hall.left", scope: "card:hall", key: "left", label: "pass" },
  { id: "hall.up", scope: "card:hall", key: "up", label: "maybe" },
  { id: "hall.right", scope: "card:hall", key: "right", label: "hire" },
  { id: "hall.space", scope: "card:hall", key: "space", label: "lock / unlock the row" },
  { id: "hall.m", scope: "card:hall", key: "m", label: "the maybe pile" },
  // card:store
  { id: "store.left", scope: "card:store", key: "left", label: "previous species" },
  { id: "store.right", scope: "card:store", key: "right", label: "next species" },
  { id: "store.up", scope: "card:store", key: "up", label: "pass" },
  { id: "store.down", scope: "card:store", key: "down", label: "back" },
  { id: "store.space", scope: "card:store", key: "space", label: "lock / unlock the row" },
  { id: "store.e", scope: "card:store", key: "e", label: "rename" },
  { id: "store.enter", scope: "card:store", key: "enter", label: "adopt" },
  // card:hall-pile
  { id: "hall-pile.x", scope: "card:hall-pile", key: "x", label: "drop" },
  { id: "hall-pile.esc", scope: "card:hall-pile", key: "esc", label: "back to the hall" },
  // card:help
  { id: "help.esc", scope: "card:help", key: "esc", label: "back to …" },
  // the reader (full-screen thread); its card keys, threadActions, work there too
  { id: "reader.reply", scope: "reader", key: "r i enter", label: "reply" },
  { id: "reader.line", scope: "reader", key: "j k", label: "scroll a line" },
  { id: "reader.page", scope: "reader", key: "pgup pgdn", label: "scroll a page" },
  { id: "reader.ends", scope: "reader", key: "home end", label: "the oldest / the newest" },
  { id: "reader.back", scope: "reader", key: "esc q", label: "back to the room" },
  // the sandbox's play keys
  { id: "play.d", scope: "sandbox-play", key: "d", label: "doorbell" },
  { id: "play.e", scope: "sandbox-play", key: "e", label: "event" },
  { id: "play.t", scope: "sandbox-play", key: "t", label: "treat" },
  { id: "play.f", scope: "sandbox-play", key: "f", label: "fire drill" },
  { id: "play.n", scope: "sandbox-play", key: "n", label: "night" },
  { id: "play.w", scope: "sandbox-play", key: "w", label: "weather" },
  { id: "play.p", scope: "sandbox-play", key: "p", label: "pet" },
  { id: "play.c", scope: "sandbox-play", key: "c", label: "call over" },
] as const satisfies readonly Binding[]

export type KeyId = (typeof KEYS)[number]["id"]
const byId = new Map<string, Binding>(KEYS.map((b) => [b.id, b]))

/** a card's action row without its handler: `{ ...bind("thread.r"), run }`; `label` is for the rows whose words carry live state */
export const bind = (id: KeyId, label?: string): { key: string; label: string } => {
  const b = byId.get(id)!
  return { key: b.key, label: label ?? b.label }
}

/** a scope's listed keys, for the foot, the help card and the sandbox's line */
export const hints = (scope: Scope): { key: string; label: string }[] =>
  KEYS.filter((b) => b.scope === scope && !("quiet" in b)).map((b) => ({ key: b.key, label: b.label }))

/** the helper scopes a card's action list is built from; a card's keys are its own scope's plus these */
export const CARD_PARTS: Record<string, readonly Scope[]> = {
  "card:crew": ["card:seat"],
  "card:person": ["card:live", "card:thread", "card:seat"],
  "card:thread": ["card:live", "card:thread"],
  "card:needs": ["card:need"],
  "card:decide": ["card:need"],
  reader: ["card:thread"],
}

/** the scopes that are a helper's alone — never a card the pane shows by itself */
export const HELPERS: readonly Scope[] = ["card:need", "card:thread", "card:seat", "card:live", "card:back"]

/** Two meanings of one key live on one screen; `winner` is the scope that answers it, over the `over` scopes (`card:*` for any card). */
export type Shadow = { key: string; winner: Scope; over: readonly Scope[]; why: string }
const PLAY_WINS = "the sandbox's play keys run before a card's actions (`playable` hides the card's row there)"
export const SHADOWS: readonly Shadow[] = [
  ...["d", "e", "t", "f", "n", "w", "p", "c"].map((key) => ({ key, winner: "sandbox-play" as const, over: ["card:*", "global"] as const, why: PLAY_WINS })),
  { key: "R", winner: "card:*", over: ["global"], why: "a card's own action runs before the global reload, which only a card without an R of its own reaches" },
  { key: "p", winner: "card:*", over: ["global"], why: "a card's own action runs before the global pat Nina" },
  { key: "i", winner: "reader", over: ["global"], why: "the reader takes i for its reply box" },
  { key: "q", winner: "reader", over: ["global"], why: "the reader's q goes back to the room, not out of the TUI" },
  { key: "v", winner: "card:person", over: ["card:thread"], why: "the person card lists the thread's actions without its v (the conversation is theirs)" },
  { key: "v", winner: "card:need", over: ["card:need"], why: "needActions keeps the first v: a blocked PR's names the PR, the rest read the thread" },
]

/** One key, several meanings across cards: every binding of `key` is listed, so a new meaning must be declared here. */
export type Polysemy = { key: string; ids: readonly KeyId[] }
export const POLYSEMY: readonly Polysemy[] = [
  { key: "R", ids: ["global.R", "need.R.job_failed", "need.R.publish_failed", "need.R.release_failed", "thread.R", "pages.R", "settings.R"] },
  { key: "S", ids: ["thread.S", "home.S", "crew.S", "ticket.S", "boss.S", "pet.S.cat"] },
  { key: "d", ids: ["need.d.job_failed", "need.d.rollout", "need.d.publish_failed", "need.d.quota", "need.d.decide", "thread.d", "ticket.d", "calendar.d", "memory.d", "boss.d", "ideas.d", "play.d"] },
  { key: "x", ids: ["need.x.issue", "thread.x", "build.x", "review.x", "settings.x", "hall-pile.x"] },
  { key: "c", ids: ["live.c", "home.c", "crew.c", "pet.c.cat", "play.c"] },
  { key: "f", ids: ["home.f", "needs.f", "play.f"] },
  { key: "p", ids: ["global.p", "review.p", "decide.p", "pet.p.cat", "pet.p.dog", "play.p"] },
]
