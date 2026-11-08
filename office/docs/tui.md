# office/tui/ — the standalone terminal app

`tui/` — the standalone terminal app (`mise run office:run`), Linux and macOS; `mise run
office:build` compiles it to one self-contained executable per platform (`office/dist/`).
`mise run office:sandbox` (`--sandbox`, or `OFFICE_SANDBOX=1`) runs it on a made-up world, no server: `tui/sandbox.ts` is the
world, `data.useFake` the one seam in `data.ts`; one play key, `E`, opens a numbered card (shown once, on the first `office:sandbox` launch, under `OFFICE_PLAY_INTRO=1`); digits pick the toy, `0` turns to page 2 (one row per event, and `chainReaction`: Gary, then each scene's chain to its end), so no letter shadows a card.
The sandbox keeps its looks, souls, hall, cast, pets and store in `$TMPDIR/tlon-sandbox/` (the `TLON_*` vars still win), so a pretend hire or adopt never reaches the machine's files.
The hiring hall (`h` from home; `kit/hall.ts` the pure candidate — `roll(seed, taken)` is seeded, no model, no I/O; a lock is kept by `pass` baking it into the overrides —
`tui/hall.ts` its card rows): ← pass, ↑ maybe (the pile, `l` lists it), → hire, space locks a row so a pass keeps it, `e` edits the lit row (name, pitch and soul by prompt; archetype/grade/specialty cycle the roster vocabulary; a slot row opens the look card on a draft of the candidate's look, whose `s` saves it as `overrides.look` — never `looks.json` until hired) as an edit over the seed; `W` draws the candidate's soul and pitch (`data.draftSoul` → `POST /api/workspaces/:id/hire/draft`, `Server.Soul.preview`: nothing written or seated; the render never calls it) and stores them as the `soul`/`pitch`/`drawn` edits, so `e` edits the draft and → hires what was seen (`s` is taken: sort). `hall.json`
(`TLON_HALL`, polled like `looks.json`) holds seed + locks + edits + pile, never the rendered card; an edited name that fails `Server.Soul`'s name check is dropped on load, so it never reaches a file name. → hires — onto the toy's bench in the
sandbox, through `data.hire` (`POST /api/workspaces/:id/coworkers`) on a live office — and keeps the candidate's look in `looks.json` and its soul in the souls dir (never over one already there).
The cast editor, the god view (`` ` `` from home; `tui/cast.ts` its rows, pure): one row per bench seat, one cell per field —
name, archetype, look, soul, voice, grade, specialty, model; ←/→ the lit field, `}` the Office tab (the wackiness dials).
⏎ hands the lit cell to the editor that already owns it (the look card, the soul in `$EDITOR` like the dump — souls/<name>.md
made blank when absent, never overwritten — the persona and model pickers), `y` rerolls look, grade or specialty, `-` lets the
seat go; name and archetype only show (no server route renames or retypes a seat). Grade and specialty have no server field:
`cast.json` (`TLON_CAST`, `kit/cast.ts`, polled like `looks.json`) keeps them by seat name.
The pet store (`*` from home; `kit/store.ts` the pure candidate — `roll(species, seed, taken)`, seeded, no model, no I/O —
`tui/store.ts` its card rows): ←/→ the shelf (every species, each into the slot its family belongs to: cat, dog, rabbit, bird, hamster, pet rock, A Bao A Qu), ↑ pass,
↓ back, space locks a row, `e` renames, ⏎ adopts into the species' slot — the occupant leaves by the door (one pet per slot, no
history). `store.json` (`TLON_STORE`) holds species + seed + locks + edits. A new species is data: frames in `SPECIES_ART`, a
`SPECIES_VOICE` pack, a `SPECIES_BASE` row and a `SLOT_SPECIES` entry (`fillArt` lets it ship `sit` alone).
`main.ts` is the room, its detail pane's cards (Nina's has her temperament rows, a live preview and `_` to save, `⏎` cycles the lit row) and the finder (`/`); `talk.ts` what `m` (to a person) and `'` (to the office) post, on the workspace's front desk (the server's lobby thread); `reader.ts` a thread
full-screen with its composer (a thread opens, as its card or in the reader, with its reply box focused — unfocused when it has an open prompt, so 1–9 answer at once, or when another surface pushed it (`data.focus`), which never takes your keys unasked: ⏎ sends,
the first esc leaves the box — drawn still, the thread's keys live, `r` or ⏎ back in (⏎ on a running coworker's card steps into their session) — the second esc goes back);
ctrl+] is the room from anywhere — a card, a reply box, an input, the finder, the reader, a zoomed terminal — the room with
nothing open over it (the screen, not the workspace's front desk, the standing thread `talk.ts` posts to); esc stays one step back, and every
hint that says how to get out names it `ctrl+] room` (`GLOBALS` in the foot, from `tui/keys.ts`); it never drops what you were writing: an input's text
comes back when the same input is asked again, and a reply's draft is the thread's (`cardReply`), its card and its reader alike; `editor.ts` the text editing every input shares; `fuzzy.ts` the
finder's matcher; `order.ts` how list cards sort and group (`s` steps the sort on the crew, a board column and the in-tray; `g` the crew's grouping — the cursor stays on its row); `when.ts` reads a schedule's "when" (a cron, or a local time). `V` on a workline thread reviews its branch: the diff with a line cursor, `⏎`/`e` a note on the line, `"` on the file, `>`/`<` hunks, `}`/`{` files, `m` submits the notes with a verdict (comment, request changes, approve); unsent notes are kept per thread. The crew screen has tabs (`}`): each crew the operator has named, then everyone, the crews not on dimmed; `>` moves the selected coworker to the next crew (or every crew), `n` puts them on a new one by name, and `%` puts the next crew on (also `shifts` in the finder); a click on the header's crew (shown once a workspace has crews) does the same. The finder's `pencils down`, `lights out` (confirmed) and `back to work` are the office's stop controls (`Server.Pause`); while one is on, the header carries its mark (`✎ pencils down` / `◼ lights out`), and a click on it offers back to work. The arcade's
cabinets open terminal games (whichever the machine has installed) in the office's own tmux,
zoomed like a coworker's terminal. `⏎` on the dump row of a home workspace's LIFE card opens the dump,
the one page the operator pours everything into, in their own `$VISUAL`/`$EDITOR` the same way: every save
goes to the server (`PUT /api/life/:ws/dump`), a save the server didn't take is retried on the next write, leave, open or refresh, and `l` lists the
earlier pages each save kept, to read or put back. That tmux is `TLON_OFFICE_TMUX` (default `tlon-office`), its
files under `$XDG_RUNTIME_DIR/<it>` (the dump's under `$XDG_STATE_HOME/tlon/<it>`, so unsent words survive a reboot), so a drive's never touch the operator's. It is the
operator's surface. Its header carries one count, the phone (`☎ N waiting on you`, ringing while N > 0,
from `GET /api/office/needs?by=surface` — `kit/surfaces.ts`); the room's answering machine blinks for
information (played, it is heard) and the sheriff's clipboard by the door holds what the crew owns.
`i` (or a click on the count) opens the inbox by surface with each item's own actions: PHONE, MACHINE,
then SETTLED BY UQBAR (the day's digest: `u` overrules one, back to Uqbar), CLIPBOARD, then WITH UQBAR
(waiting on Uqbar's verdict, never counted on the phone). Those two groups fill only under the
server's `uqbar_routing` setting (the settings screen, `S`; default off). A
passed-up row shows Uqbar's `tip:`. A click on the header's `⚠` warning opens the rack (`H`), and a TUI on an older
office than main offers `R` to reload itself. Work that lands dark hides behind a server flag,
read only from the snapshot (`flagOn` in `kit/types.ts`): `B`, build mode, is there only with
`build_mode` on. A running coworker's card shows their activity timeline
(`timeline.ts`, from the thread view's `activity`, which the harnesses' tool hooks feed: one line per tool call, a glyph and colour per kind, grouped by coworker in their shirt colour, a rule per fresh turn, newest at the bottom, scrolled with the card; `=` the conversation, ⏎ step into their real screen). Under the room the pane splits: what you clicked on the left, what you can
do to it on the right — each card's actions (`detail()`) are its keys, its clickable list and
its docs at once, so they cannot drift apart. Every key is written down once, in `tui/keys.ts`
(scope, key, label, mode): a card's rows are `{ ...bind("thread.r"), run }`, and the foot, the help card
and the sandbox's play line read the same table — a new key is a row there, never a literal `key: "x"`
in `main.ts`. `test/keys.test.ts` reads the table and fails when a key has two `verb`s anywhere (letters,
symbols and esc; ⏎, space and the arrows are the lit row, digits a card's numbered menu) or a screen binds
one twice: **one meaning per key**, so a hint never needs a mode to read. A new key is a free letter or
symbol and a `verb`, never a second use of a taken one. The reader's handlers are still `case`s in `reader.ts`; only its hints come from the table. A card's rows scroll (`tui/pane.ts`: with the
selection, or pgup/pgdn and the wheel, `↑/↓ N more` where rows hide); the foot lists the actions
the column can't show — all of them on a terminal too narrow for it — then the global keys; `?` opens the help card (that card's keys, the globals, the reader's, the sandbox's play key). Popups only where a choice needs a list (the finder).
