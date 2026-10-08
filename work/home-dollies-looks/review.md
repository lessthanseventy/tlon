# Review — home-dollies-looks (round 2)

**Verdict: approve.**

Round 1's blocker is fixed. The editor now saves through `trimCustom` (kit/looks.ts), so an all-"." view is dropped instead of drawing an invisible figure. The two new tests in test/looks.test.ts cover a front-only draw and a blank draw. The most recent `mise run check` on the branch exited 0 (server:check 9 passed, 0 failed, 1 skipped).

I read the diff (`git diff main...HEAD`). I did not run the suite or drive the TUI myself.

## Spec compliance
- **pngjs boundary holds:** only `office/cli.ts` imports it. `kit/snap.ts` is pure, and nothing under `kit/` or `tui/` pulls in pngjs. This is the operator's condition.
- **Mise task and live re-read:** `office:import-sprite` exists in `tasks/office.toml`. looks.json is re-read live, using the same mtime poll as palette.json.
- **No change for agents without an entry:** the `Look` additions are optional, and `skinRole` falls back to `ROLE.prose`.

## Open minors (non-blocking; the builder already names 2–5)
1. **Malformed `custom` can crash the render.** looks.json rows are not validated, and `overlay` does `rows[i]!.split`. A hand-edited `custom` with fewer than 22 rows, or one that is not an array, throws in `figure`, and the TUI's `uncaughtException` handler exits. The importer always writes 22×12, so only hand edits hit this. Validate shape in `useLookOverrides`, or drop a bad `custom`, as a follow-up.
2. **Importer paint map ignores saved overrides.** `paints(shirtOf(null), lookOf(name))` skips `overrideFor`, so a saved `skinRole` is not used when snapping. It also uses the gold shirt, so `s`, `y` and `o` tie on colour and `s` always wins. Likewise `b`/`c` and `g`/`e` resolve to the first char. This is lossy but deterministic.
3. **`esc` in the editor restores only the current view.** All drafts are discarded when the card reopens, so the effect is cosmetic.
4. **Mirror applies in the side view.** It should be off or ignored there.
5. **`saveLook` freezes every derived field** (hair, decor, blink and so on) into looks.json. Later changes to the hash-derived defaults will not reach an agent that was saved once.
6. **`followLooks` never clears overrides** if looks.json is deleted or becomes invalid JSON. It keeps the last good set until restart.
7. **`import-sprite` decodes the PNG twice** and crashes on invalid existing looks.json JSON. Fine for a dev tool.
