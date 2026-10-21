**Verdict: approve** (3b2640c, #549)

The diff does what the title says. Both files now record every `mkdtempSync` dir in `made` and run `rmSync(..., {recursive, force})` on each one in `afterEach`. `splice(0)` empties the list, so dirs are never removed twice and the list never grows.

Evidence (lonnrot ran it):
1. `TMPDIR=$(mktemp -d) bun test test/hall.test.ts test/whimsy-file.test.ts`: 35 pass, 0 fail. The isolated TMPDIR has **0** entries left afterwards.
2. The other office tests that call `mkdtemp`: home, store and souls left nothing behind in an isolated TMPDIR. The rest of the `grep mkdtemp office/test` hits already import `rmSync` and clean up at file level.

No findings.
