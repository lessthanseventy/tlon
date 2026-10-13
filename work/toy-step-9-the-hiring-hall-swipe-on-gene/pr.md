# office: the hiring hall (toy step 9, ticket #65) — sandbox half

**What.** A hall in the office (`h` from home): one seeded candidate at a time, three views, name,
archetype/grade/specialty, a pitch and a row per part slot. ← pass, ↑ maybe (pile, `m` to browse),
→ hire, space locks a row so a pass keeps it. State is `hall.json` (`TLON_HALL`): seed + locks +
edits + pile, never the rendered card, so a restart re-renders the same person.
`kit/hall.ts` is the pure core (`roll`, `candidateOf`, `pass`, `maybe`, `bringBack`, `toggleLock`);
`tui/hall.ts` the card rows; `tui/sandbox.ts` gains `hire`. In `--sandbox` a hire seats on the toy
bench and writes a look and a soul skeleton into `$TMPDIR/tlon-sandbox/` (the toy's looks/souls/hall
moved there so a pretend hire never reaches the machine's files).

**Not here (blocked on `Server.Soul` reaching main via souls-step-2).** Plan tasks 1, 2, 6 (office
hire endpoint + confirm modal) and 7 (model soul/pitch on demand). In the office `→` says so and seats
nobody. #66/#68 seams kept (`Candidate` is kind-agnostic); nothing built for them.

**Also not built.** `e` (spec §2: edit the look from the hall) is in neither plan task 5 nor this
build, so `Overrides.parts` has no UI producer yet (only locks write it). Grades/specialties in
main.ts are constants, not the roster vocabulary (spec §3). A hired name is checked against the
bench (a locked, already-taken name is not hired twice and not carried to the next card); a
hand-edited `hall.json` name is not yet checked against `Server.Soul`'s name regex.

**Closes** part of #65; the ticket stays open for the server half.

**Checked.** `bun test` in office: 514 pass in-sandbox; the 5 tmux-socket tests that the bash sandbox
blocks (`refresh`, `terminal`) pass unsandboxed (4/4). `bunx tsc --noEmit` clean. Driven headless in
the sandbox: `h ← ← ↑ space →` hires `ashe`; `souls/ashe.md`, `looks.json` and `hall.json` (seed,
locked name, pile entry) land in the sandbox dir.
