# office: `e` edits the lit row in the hiring hall (spec §2 `e`, ticket #298)

**What.** In the hall, `e` edits the selected card row: name, pitch and soul by prompt (a name must pass
`Server.Soul`'s check and not be taken; blank pitch/soul refused); archetype, grade, specialty cycle the
roster vocabulary; a slot row opens the existing `look` card over a draft of the candidate's look, and its
`_` save writes the whole draft into `hall.json` as `overrides.look` (never `looks.json` — the candidate has
no name there until hired; a hire writes what the operator saw). The soul text is `overrides.soul`. A pass
drops an edit unless the row is locked. The card gains a last `soul` row (not lockable). Pure `editField` /
`setLook` in `kit/hall.ts`; the `look` and `look-editor` modes carry `hall: true`; key `hall.e`.

**Closes** ticket #298 (the `e` half; `s` stays plan task 7).

**Checked.** Tests first (red: missing `setLook`), then green. `bun test` in office: 913 pass, 0 fail; `bunx tsc --noEmit`
clean. Driven through `scripts/office-drive.sh` (sandbox): `h`, 5×Down to the first slot, `e` opens `LOOK · RUPAR`, Enter
cycles skin, `_` returns to the hall; shift-tab to the soul row, `e`, type, Enter: the row shows the text. The sandbox's
hall.json then held `overrides.look.skinRole = "builder"` and `overrides.soul` ending `sleepslate`.
