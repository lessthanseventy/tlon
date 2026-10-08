# Review — home-dollies-looks (round 3, after the rebase onto 46f92a3)

**Verdict: approve.**

This round only re-checks the rebase. The earlier approve (round 2) still holds: the `trimCustom` fix, the pngjs boundary and the live looks.json re-read are unchanged.

I read `git diff main...HEAD -- office/kit/sim.ts`, the file that conflicted. The resolution keeps both sides:
- main's `warmth` and `cooled` fields are intact.
- The branch's `lookGen` and `overrideFor` are merged into the `Actor` type, the look refresh on an existing actor, and the new-actor construction.
- The branch is based on current main (merge-base 46f92a3).

The latest `mise run check` on the branch exited 0 (server:check 9 passed, 0 failed, 1 skipped).

I did not run the suite or drive the TUI myself.

## Open minors (non-blocking, carried from round 2)
1. A malformed `custom` in a hand-edited looks.json can crash the render. Validate its shape in `useLookOverrides`.
2. The importer's paint map ignores saved `skinRole` overrides.
3. `esc` in the editor restores only the current view.
4. The mirror toggle also applies in the side view.
5. `saveLook` freezes every derived field into looks.json.
