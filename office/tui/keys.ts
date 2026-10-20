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
  /** what the key does, in one or two words: a key has exactly one verb across the whole table (`⏎` and the arrows are the card's lit row, so they are exempt); the label says the particulars */
  verb?: string
  /** handled, but not listed in the foot or the help card's "everywhere" */
  quiet?: boolean
}

/** the look editor's paint letters: each paints its colour, so they are the editor's alone */
export const LEGEND_CHARS = ["h", "f", "k", "s", "p", "b", "y", "c", "g", "e", "w", "r", "o"] as const

export const KEYS = [
  // global: the foot's hints, the help card's "everywhere"
  { id: "global.find", scope: "global", key: "/", label: "find", verb: "find" },
  { id: "global.talk", scope: "global", key: "'", label: "talk to the office" },
  { id: "global.inbox", scope: "global", key: "i", label: "inbox", verb: "inbox" },
  { id: "global.crew", scope: "global", key: "c", label: "crew", verb: "crew" },
  { id: "global.workspace", scope: "global", key: "[ ]", label: "workspace" },
  { id: "global.help", scope: "global", key: "?", label: "help" },
  { id: "global.back", scope: "global", key: "esc", label: "back", verb: "back" },
  { id: "global.room", scope: "global", key: "ctrl+]", label: "room" },
  { id: "global.quit", scope: "global", key: "q", label: "quit", verb: "quit" },
  // global, handled in onKey's switch but not hinted
  { id: "global.tab", scope: "global", key: "tab", label: "next coworker", quiet: true },
  { id: "global.R", scope: "global", key: "R", label: "reload the TUI (when it is out of date)", mode: "when the server has a newer office", quiet: true, verb: "reload" },
  { id: "global.p", scope: "global", key: "p", label: "pat Nina", quiet: true, verb: "pat" },
  { id: "global.U", scope: "global", key: "U", label: "Uqbar's volume", quiet: true, verb: "Uqbar" },
  { id: "global.centre", scope: "global", key: ".", label: "centre the room", quiet: true },
  { id: "global.need", scope: "global", key: ",", label: "to the first thing waiting", quiet: true },
  // card:need
  { id: "need.A.gate", scope: "card:need", key: "A", label: "approve", mode: "gate", verb: "approve" },
  { id: "need.u.ask", scope: "card:need", key: "u", label: "hand it to Uqbar (decides and acts as you)", mode: "ask", verb: "hand to Uqbar" },
  { id: "need.1.seats", scope: "card:need", key: "+", label: "raise the cap to …", mode: "seats", verb: "add" },
  { id: "need.R.job_failed", scope: "card:need", key: "y", label: "run it again", mode: "job_failed", verb: "again" },
  { id: "need.d.job_failed", scope: "card:need", key: "d", label: "dismiss", mode: "job_failed", verb: "remove" },
  { id: "need.r.question", scope: "card:need", key: "r", label: "reply", mode: "question", verb: "reply" },
  { id: "need.r.stalled", scope: "card:need", key: "r", label: "tell the lead what to do (wakes them)", mode: "stalled", verb: "reply" },
  { id: "need.V.verify_failed", scope: "card:need", key: "y", label: "run verify again", mode: "verify_failed", verb: "again" },
  { id: "need.R.publish_failed", scope: "card:need", key: "y", label: "republish (push, open its PR)", mode: "publish_failed", verb: "again" },
  { id: "need.R.release_failed", scope: "card:need", key: "y", label: "retry the cut", mode: "release_failed", verb: "again" },
  { id: "need.b.pr_blocked", scope: "card:need", key: "(", label: "rebase it (back in the merge queue)", mode: "pr_blocked", verb: "rebase" },
  { id: "need.L.pr_blocked", scope: "card:need", key: ")", label: "close and reland (back to build)", mode: "pr_blocked", verb: "reland" },
  { id: "need.n.stalled", scope: "card:need", key: "^", label: "nudge the lead (wakes them)", mode: "stalled", verb: "nudge" },
  { id: "need.o.stalled", scope: "card:need", key: "@", label: "hand it to…", mode: "stalled", verb: "hand off" },
  { id: "need.x.stalled", scope: "card:need", key: "x", label: "close it…", mode: "stalled", verb: "done" },
  { id: "need.v.pr_blocked", scope: "card:need", key: "v", label: "show me: the thread…", mode: "pr_blocked", verb: "read" },
  { id: "need.d.rollout", scope: "card:need", key: "x", label: "done", mode: "rollout", verb: "done" },
  { id: "need.X.stranded", scope: "card:need", key: "X", label: "take the checkout down (branch kept)", mode: "stranded", verb: "clear" },
  { id: "need.g.issue", scope: "card:need", key: "$", label: "get it fixed (a ticket, routed)", mode: "issue", verb: "fix" },
  { id: "need.x.issue", scope: "card:need", key: "x", label: "resolve…", mode: "issue", verb: "done" },
  { id: "need.d.publish_failed", scope: "card:need", key: "x", label: "opened by hand (the command is above): its PR's url…", mode: "publish_failed", verb: "done" },
  { id: "need.h.no_seat", scope: "card:need", key: "+", label: "hire a …", mode: "no_seat", verb: "add" },
  { id: "need.o.no_seat", scope: "card:need", key: "@", label: "hand it to…", mode: "no_seat", verb: "hand off" },
  { id: "need.A.tool_denied", scope: "card:need", key: "A", label: "allowed it: the rule is in your own settings (wakes the lead)", mode: "tool_denied", verb: "approve" },
  { id: "need.r.tool_denied", scope: "card:need", key: "r", label: "did it by hand: tell the lead (wakes them)", mode: "tool_denied", verb: "reply" },
  { id: "need.B.tool_denied", scope: "card:need", key: "B", label: "back to build…", mode: "tool_denied", verb: "build" },
  { id: "need.u.tool_denied", scope: "card:need", key: "u", label: "hand it to Uqbar", mode: "tool_denied", verb: "hand to Uqbar" },
  { id: "need.P.quota", scope: "card:need", key: "|", label: "pencils down", mode: "quota", verb: "pause" },
  { id: "need.d.quota", scope: "card:need", key: "d", label: "wait for the reset (put away until it clears)", mode: "quota", verb: "remove" },
  { id: "need.d.decide", scope: "card:need", key: "d", label: "put away", mode: "decide-level, ask or stalled", verb: "remove" },
  { id: "need.v", scope: "card:need", key: "v", label: "read the thread", mode: "any other", verb: "read" },
  { id: "need.t", scope: "card:need", key: "z", label: "look over their shoulder", verb: "zoom" },
  // card:thread
  { id: "thread.v", scope: "card:thread", key: "v", label: "read it all", verb: "read" },
  { id: "thread.r", scope: "card:thread", key: "r", label: "reply", verb: "reply" },
  { id: "thread.u", scope: "card:thread", key: "u", label: "hand to Uqbar", verb: "hand to Uqbar" },
  { id: "thread.a", scope: "card:thread", key: ":", label: "call in the Aleph", verb: "call in" },
  { id: "thread.A", scope: "card:thread", key: "A", label: "approve: …", verb: "approve" },
  { id: "thread.>", scope: "card:thread", key: ">", label: "advance the workline", verb: "next" },
  { id: "thread.S", scope: "card:thread", key: "+", label: "raise the cap (settings)", verb: "add" },
  { id: "thread.t", scope: "card:thread", key: "z", label: "look over their shoulder", verb: "zoom" },
  { id: "thread.g", scope: "card:thread", key: "g", label: "git (lazygit)", verb: "git" },
  { id: "thread.d", scope: "card:thread", key: "l", label: "read its docs (spec, plan…)", verb: "list" },
  { id: "thread.R", scope: "card:thread", key: "V", label: "review its branch", verb: "review" },
  { id: "thread.h", scope: "card:thread", key: "@", label: "hand off to…", verb: "hand off" },
  { id: "thread.P", scope: "card:thread", key: "#", label: "move to project…", verb: "project" },
  { id: "thread.x", scope: "card:thread", key: "x", label: "close as done", verb: "done" },
  { id: "thread.D", scope: "card:thread", key: "d", label: "delete for good", verb: "remove" },
  // card:seat
  { id: "seat.M", scope: "card:seat", key: "M", label: "model…", verb: "model" },
  { id: "seat.y", scope: "card:seat", key: "&", label: "ask before acting / allow without asking", verb: "toggle ask" },
  { id: "seat.E", scope: "card:seat", key: "e", label: "persona…", verb: "edit" },
  { id: "seat.C", scope: "card:seat", key: "X", label: "clear context (fresh next time)", verb: "clear" },
  { id: "seat.-", scope: "card:seat", key: "-", label: "let go", verb: "remove" },
  // card:live
  { id: "live.enter", scope: "card:live", key: "enter", label: "step into their session" },
  { id: "live.c", scope: "card:live", key: "=", label: "their activity / the conversation", verb: "toggle view" },
  // card:back
  { id: "back.esc", scope: "card:back", key: "esc", label: "back", verb: "back" },
  // card:home
  { id: "home./", scope: "card:home", key: "/", label: "find anything", verb: "find" },
  { id: "home.i", scope: "card:home", key: "i", label: "inbox — everywhere", verb: "inbox" },
  { id: "home.n", scope: "card:home", key: "n", label: "new thread", verb: "new" },
  { id: "home.N", scope: "card:home", key: "I", label: "new ticket", verb: "new ticket" },
  { id: "home.c", scope: "card:home", key: "c", label: "crew", verb: "crew" },
  { id: "home.t", scope: "card:home", key: "t", label: "tickets & worklines", verb: "tickets" },
  { id: "home.w", scope: "card:home", key: "w", label: "in-tray", verb: "tray" },
  { id: "home.!", scope: "card:home", key: "!", label: "triage", verb: "triage" },
  { id: "home.a", scope: "card:home", key: "a", label: "calendar", verb: "calendar" },
  { id: "home.o", scope: "card:home", key: "o", label: "notes", verb: "notes" },
  { id: "home.b", scope: "card:home", key: "b", label: "memory", verb: "memory" },
  { id: "home.H", scope: "card:home", key: "H", label: "the rack (health)", verb: "rack" },
  { id: "home.L", scope: "card:home", key: "L", label: "life", verb: "life" },
  { id: "home.B", scope: "card:home", key: "B", label: "build mode", verb: "build" },
  { id: "home.f", scope: "card:home", key: "f", label: "filing cabinet", verb: "filing cabinet" },
  { id: "home.W", scope: "card:home", key: "O", label: "workspaces", verb: "workspaces" },
  { id: "home.S", scope: "card:home", key: "S", label: "settings (the running system)", verb: "settings" },
  { id: "home.h", scope: "card:home", key: "h", label: "the hiring hall", verb: "hall" },
  { id: "home.P", scope: "card:home", key: "*", label: "the pet store", verb: "pet store" },
  { id: "home.q", scope: "card:home", key: "q", label: "quit", verb: "quit" },
  // card:crew
  { id: "crew.v", scope: "card:crew", key: "}", label: "tab: …", verb: "next group" },
  { id: "crew.c", scope: "card:crew", key: ">", label: "… on …", verb: "next" },
  { id: "crew.n", scope: "card:crew", key: "n", label: "a new crew…", verb: "new" },
  { id: "crew.S", scope: "card:crew", key: "%", label: "put the … crew on", verb: "switch shift" },
  { id: "crew.+", scope: "card:crew", key: "+", label: "hire", verb: "add" },
  { id: "crew.P.paused", scope: "card:crew", key: "|", label: "back to work", mode: "paused", verb: "pause" },
  { id: "crew.P.running", scope: "card:crew", key: "|", label: "pencils down: nothing new, all stop after their turn", mode: "running", verb: "pause" },
  { id: "crew.L", scope: "card:crew", key: "~", label: "lights out…", verb: "lights out" },
  { id: "crew.s", scope: "card:crew", key: "s", label: "sort: … → …", verb: "sort" },
  { id: "crew.g", scope: "card:crew", key: "G", label: "group: … → …", verb: "group" },
  // card:person
  { id: "person.m", scope: "card:person", key: "m", label: "talk", verb: "say" },
  { id: "person.v", scope: "card:person", key: "v", label: "the conversation", verb: "read" },
  { id: "person.w", scope: "card:person", key: ";", label: "read #…", verb: "read" },
  { id: "person.l", scope: "card:person", key: "\\", label: "look", verb: "look" },
  // card:column
  { id: "column.n", scope: "card:column", key: "n", label: "new ticket", verb: "new" },
  { id: "column.s", scope: "card:column", key: "s", label: "sort: … → …", verb: "sort" },
  { id: "column.right", scope: "card:column", key: "right", label: "next column (← →)" },
  { id: "column.K", scope: "card:column", key: "K", label: "move up", verb: "move up" },
  { id: "column.J", scope: "card:column", key: "J", label: "move down", verb: "move down" },
  // card:ticket
  { id: "ticket.S", scope: "card:ticket", key: "enter", label: "start it with the lead" },
  { id: "ticket.s", scope: "card:ticket", key: "@", label: "send to the manager to staff", verb: "hand off" },
  { id: "ticket.e", scope: "card:ticket", key: "e", label: "edit the title", verb: "edit" },
  { id: "ticket.b", scope: "card:ticket", key: "+", label: "blocked by…", verb: "add" },
  { id: "ticket.u", scope: "card:ticket", key: "-", label: "unblock", verb: "remove" },
  { id: "ticket.K", scope: "card:ticket", key: "K", label: "move up", verb: "move up" },
  { id: "ticket.J", scope: "card:ticket", key: "J", label: "move down", verb: "move down" },
  { id: "ticket.d", scope: "card:ticket", key: "d", label: "delete", verb: "remove" },
  // card:calendar
  { id: "calendar.n", scope: "card:calendar", key: "n", label: "schedule something", verb: "new" },
  { id: "calendar.e", scope: "card:calendar", key: "e", label: "edit it", verb: "edit" },
  { id: "calendar.space", scope: "card:calendar", key: "space", label: "pause it / resume it" },
  { id: "calendar.r", scope: "card:calendar", key: "y", label: "run it now", verb: "again" },
  { id: "calendar.d", scope: "card:calendar", key: "d", label: "delete it", verb: "remove" },
  // card:life
  { id: "life.E", scope: "card:life", key: "l", label: "earlier pages", verb: "list" },
  { id: "life.r", scope: "card:life", key: "n", label: "new routine", verb: "new" },
  { id: "life.Q", scope: "card:life", key: "Q", label: "new quest", verb: "new quest" },
  // card:pages
  { id: "pages.esc", scope: "card:pages", key: "esc", label: "life", verb: "back" },
  { id: "pages.enter", scope: "card:pages", key: "enter", label: "read it" },
  { id: "pages.R", scope: "card:pages", key: "Y", label: "put it back", verb: "undo" },
  // card:runs
  { id: "runs.r", scope: "card:runs", key: "y", label: "run it now", verb: "again" },
  { id: "runs.esc", scope: "card:runs", key: "esc", label: "the calendar", verb: "back" },
  // card:run
  { id: "run.esc", scope: "card:run", key: "esc", label: "the runs", verb: "back" },
  { id: "run.t", scope: "card:run", key: "v", label: "read its thread", verb: "read" },
  // card:notes
  { id: "notes.n", scope: "card:notes", key: "n", label: "pin a note", verb: "new" },
  // card:tray
  { id: "tray.s", scope: "card:tray", key: "s", label: "sort: … → …", verb: "sort" },
  // card:memory
  { id: "memory.a", scope: "card:memory", key: "A", label: "approve the habit", verb: "approve" },
  { id: "memory.r", scope: "card:memory", key: "d", label: "reject the habit", mode: "a habit", verb: "remove" },
  { id: "memory.d", scope: "card:memory", key: "d", label: "forget the fact", mode: "a fact", verb: "remove" },
  // card:build
  { id: "build.up", scope: "card:build", key: "up", label: "move" },
  { id: "build.down", scope: "card:build", key: "down", label: "move" },
  { id: "build.left", scope: "card:build", key: "left", label: "move" },
  { id: "build.right", scope: "card:build", key: "right", label: "move" },
  { id: "build.enter", scope: "card:build", key: "enter", label: "drop / pick up" },
  { id: "build.n", scope: "card:build", key: "n", label: "new tile (cycles the kind)", verb: "new" },
  { id: "build.x", scope: "card:build", key: "d", label: "remove", verb: "remove" },
  { id: "build.r", scope: "card:build", key: ">", label: "rotate", verb: "next" },
  { id: "build.u", scope: "card:build", key: "Y", label: "undo", verb: "undo" },
  { id: "build.esc", scope: "card:build", key: "esc", label: "leave", verb: "back" },
  // card:boss
  { id: "boss.n", scope: "card:boss", key: "n", label: "new workspace", verb: "new" },
  { id: "boss.e", scope: "card:boss", key: "e", label: "this one's settings", verb: "edit" },
  { id: "boss.S", scope: "card:boss", key: "S", label: "the running system", verb: "settings" },
  { id: "boss.d", scope: "card:boss", key: "d", label: "close this one", verb: "remove" },
  { id: "boss.+", scope: "card:boss", key: "+", label: "hire", verb: "add" },
  { id: "boss.\\", scope: "card:boss", key: "\\", label: "your look", verb: "look" },
  // card:card
  { id: "card.T", scope: "card:card", key: "1", label: "type: … → next" },
  { id: "card.s", scope: "card:card", key: "2", label: "scope: … → next" },
  { id: "card.I", scope: "card:card", key: "3", label: "icon" },
  { id: "card.+", scope: "card:card", key: "+", label: "add a repo", verb: "add" },
  { id: "card.-", scope: "card:card", key: "-", label: "remove …", verb: "remove" },
  // card:review
  { id: "review.a", scope: "card:review", key: "e", label: "note this line", verb: "edit" },
  { id: "review.A", scope: "card:review", key: "\"", label: "note the whole file", verb: "note" },
  { id: "review.x", scope: "card:review", key: "d", label: "drop its note", verb: "remove" },
  { id: "review.n", scope: "card:review", key: ">", label: "next hunk", verb: "next" },
  { id: "review.p", scope: "card:review", key: "<", label: "previous hunk", verb: "previous" },
  { id: "review.N", scope: "card:review", key: "}", label: "next file", verb: "next group" },
  { id: "review.P", scope: "card:review", key: "{", label: "previous file", verb: "previous group" },
  { id: "review.s", scope: "card:review", key: "m", label: "submit…", verb: "say" },
  // card:whimsy
  { id: "whimsy.0", scope: "card:whimsy", key: "0", label: "back to the preset's own dials" },
  // card:settings
  { id: "settings.Z", scope: "card:settings", key: "Z", label: "the wackiness dial", verb: "wackiness" },
  { id: "settings.x", scope: "card:settings", key: "d", label: "cancel the scheduled restart", verb: "remove" },
  // card:needs
  { id: "needs.f", scope: "card:needs", key: ">", label: "one at a time", verb: "next" },
  // card:babel
  { id: "babel.n", scope: "card:babel", key: "n", label: "another page", verb: "new" },
  // card:entry
  { id: "entry.m", scope: "card:entry", key: "m", label: "ask Uqbar…", verb: "say" },
  { id: "entry.t", scope: "card:entry", key: "z", label: "look over Uqbar's shoulder", verb: "zoom" },
  { id: "entry.v", scope: "card:entry", key: "v", label: "read the study", verb: "read" },
  // card:decide
  { id: "decide.n", scope: "card:decide", key: ">", label: "next", verb: "next" },
  { id: "decide.p", scope: "card:decide", key: "<", label: "previous", verb: "previous" },
  { id: "decide.l", scope: "card:decide", key: "l", label: "the whole list", verb: "list" },
  // card:ideas
  { id: "ideas.t", scope: "card:ideas", key: "I", label: "file it as a ticket", verb: "new ticket" },
  { id: "ideas.d", scope: "card:ideas", key: "d", label: "throw it out", verb: "remove" },
  // card:pet
  { id: "pet.S.cat", scope: "card:pet", key: "_", label: "save her temperament", mode: "cat", verb: "save" },
  { id: "pet.p.cat", scope: "card:pet", key: "p", label: "pat her", mode: "cat", verb: "pat" },
  { id: "pet.z.cat", scope: "card:pet", key: "1", label: "the zoomies", mode: "cat" },
  { id: "pet.y.cat", scope: "card:pet", key: "2", label: "play with the yarn", mode: "cat" },
  { id: "pet.c.cat", scope: "card:pet", key: "3", label: "come to my desk", mode: "cat" },
  { id: "pet.s.cat", scope: "card:pet", key: "4", label: "go have a nap", mode: "cat" },
  { id: "pet.b.cat", scope: "card:pet", key: "5", label: "a drink from the tub", mode: "cat" },
  { id: "pet.u.cat", scope: "card:pet", key: "6", label: "curl up in the tub", mode: "cat" },
  { id: "pet.g.cat", scope: "card:pet", key: "7", label: "go cheer someone on", mode: "cat" },
  { id: "pet.l.cat", scope: "card:pet", key: "8", label: "Nina carries a letter", mode: "cat" },
  { id: "pet.p.dog", scope: "card:pet", key: "p", label: "pat him", mode: "dog", verb: "pat" },
  { id: "pet.w.dog", scope: "card:pet", key: "9", label: "go for a walk", mode: "dog" },
  { id: "pet.o.dog", scope: "card:pet", key: "3", label: "come to my office", mode: "dog" },
  { id: "pet.s.dog", scope: "card:pet", key: "4", label: "sit", mode: "dog" },
  { id: "pet.b.dog", scope: "card:pet", key: "6", label: "bed", mode: "dog" },
  { id: "pet.g.dog", scope: "card:pet", key: "7", label: "go cheer someone on", mode: "dog" },
  // card:look
  { id: "look.s", scope: "card:look", key: "_", label: "save", verb: "save" },
  { id: "look.r", scope: "card:look", key: "y", label: "roll", verb: "again" },
  { id: "look.e", scope: "card:look", key: "e", label: "draw a custom look", verb: "edit" },
  // card:look-editor: a paint mode that takes every key before the card does, so its letters are exempt from the one-verb rule (test/keys.test.ts)
  { id: "lookedit.move", scope: "card:look-editor", key: "up down left right", label: "move the cursor" },
  { id: "lookedit.paint", scope: "card:look-editor", key: LEGEND_CHARS.join(" "), label: "letter paints" },
  { id: "lookedit.clear", scope: "card:look-editor", key: ".", label: "clears" },
  { id: "lookedit.view", scope: "card:look-editor", key: "1 2 3", label: "view" },
  { id: "lookedit.mirror", scope: "card:look-editor", key: "m", label: "mirror" },
  { id: "lookedit.save", scope: "card:look-editor", key: "enter", label: "save" },
  { id: "lookedit.discard", scope: "card:look-editor", key: "esc", label: "discard" },
  // card:hall
  { id: "hall.left", scope: "card:hall", key: "left", label: "pass" },
  { id: "hall.up", scope: "card:hall", key: "up", label: "maybe" },
  { id: "hall.right", scope: "card:hall", key: "right", label: "hire" },
  { id: "hall.space", scope: "card:hall", key: "space", label: "lock / unlock the row" },
  { id: "hall.m", scope: "card:hall", key: "l", label: "the maybe pile", verb: "list" },
  // card:store
  { id: "store.left", scope: "card:store", key: "left", label: "previous species" },
  { id: "store.right", scope: "card:store", key: "right", label: "next species" },
  { id: "store.up", scope: "card:store", key: "up", label: "pass" },
  { id: "store.down", scope: "card:store", key: "down", label: "back" },
  { id: "store.space", scope: "card:store", key: "space", label: "lock / unlock the row" },
  { id: "store.e", scope: "card:store", key: "e", label: "rename", verb: "edit" },
  { id: "store.enter", scope: "card:store", key: "enter", label: "adopt" },
  // card:hall-pile
  { id: "hall-pile.x", scope: "card:hall-pile", key: "d", label: "drop", verb: "remove" },
  { id: "hall-pile.esc", scope: "card:hall-pile", key: "esc", label: "back to the hall", verb: "back" },
  // card:help
  { id: "help.esc", scope: "card:help", key: "esc", label: "back to …", verb: "back" },
  // the reader (full-screen thread); its card keys, threadActions, work there too
  { id: "reader.reply", scope: "reader", key: "r enter", label: "reply", verb: "reply" },
  { id: "reader.line", scope: "reader", key: "j k", label: "scroll a line", verb: "scroll" },
  { id: "reader.page", scope: "reader", key: "pgup pgdn", label: "scroll a page" },
  { id: "reader.ends", scope: "reader", key: "home end", label: "the oldest / the newest" },
  { id: "reader.back", scope: "reader", key: "esc", label: "back to the room", verb: "back" },
  // the sandbox's play keys
  { id: "play.d", scope: "sandbox-play", key: "D", label: "doorbell" },
  { id: "play.e", scope: "sandbox-play", key: "E", label: "event" },
  { id: "play.t", scope: "sandbox-play", key: "T", label: "treat" },
  { id: "play.f", scope: "sandbox-play", key: "F", label: "fire drill" },
  { id: "play.n", scope: "sandbox-play", key: "N", label: "night" },
  { id: "play.w", scope: "sandbox-play", key: "W", label: "weather" },
  { id: "play.p", scope: "sandbox-play", key: "P", label: "pet" },
  { id: "play.c", scope: "sandbox-play", key: "C", label: "call over" },
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

/** the key that adds to a card's list (a new note, ticket, routine…), for the line an empty card shows */
export const adder = (scope: Scope): { key: string; label: string } | undefined => {
  const b = KEYS.find((x) => x.scope === scope && ["new", "new ticket", "new quest", "add"].includes(verbOf(x)))
  return b && { key: b.key, label: b.label }
}

/** the helper scopes a card's action list is built from; a card's keys are its own scope's plus these */
export const CARD_PARTS: Record<string, readonly Scope[]> = {
  "card:crew": ["card:seat"],
  "card:person": ["card:live", "card:thread", "card:seat"],
  "card:thread": ["card:live", "card:thread"],
  "card:needs": ["card:need"],
  "card:decide": ["card:need"],
  reader: ["card:thread"],
}

/** a helper's rows a card leaves out because it binds the key itself (person: `v` is the conversation, the reader: `r` opens its own composer) */
export const OMITS: Record<string, readonly KeyId[]> = {
  "card:person": ["thread.v"],
  reader: ["thread.r"],
}

/** the scopes that are a helper's alone — never a card the pane shows by itself */
export const HELPERS: readonly Scope[] = ["card:need", "card:thread", "card:seat", "card:live", "card:back"]

/** what a key does: its `verb`, else its label */
export const verbOf = (b: Binding): string => b.verb ?? b.label
