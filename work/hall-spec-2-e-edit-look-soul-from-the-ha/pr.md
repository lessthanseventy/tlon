# office: `e` edits the lit row in the hiring hall (spec §2 `e`, ticket #298)

**What.** In the hall, `e` edits the selected card row: name, pitch and soul by prompt (a name must pass
`Server.Soul`'s check and not be taken; blank pitch/soul refused); archetype, grade, specialty cycle the
roster vocabulary; a slot cycles its part, then none. Edits are stored as overrides over the seed, so they
persist in `hall.json`, survive a restart, and a hire writes what the operator saw. A pass drops an edit
unless the row is locked, like any other field. The card gains a last `soul` row (not lockable) so the soul
text has somewhere to be seen and edited. Pure edit fns `editField`/`cyclePartRow` in `kit/hall.ts`; keys
`hall.e` in `tui/keys.ts`; wiring in `tui/main.ts`.

**Closes** ticket #298 (the `e` half; `s` stays plan task 7).

**Checked.** Tests first (red: missing exports, 3 view failures), then green. `bun test` in office: 911 pass,
0 fail; `bunx tsc --noEmit` clean. Not driven through `office:drive`.
