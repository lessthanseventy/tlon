# office tests: remove the mkdtemp dirs they create

Closes ticket #549. `hall.test.ts` and `whimsy-file.test.ts` made a `mkdtempSync` dir per call and
never removed it, so every office gate run left `hall-*`/`whimsy-*` dirs in the shared tmp.
Each file now tracks the dirs it makes and `rmSync`s them in `afterEach`.

Checked: `ls $TMPDIR | grep -cE '^(hall|whimsy)-'` went 183 → 192 over one run before (9 leaked),
192 → 192 after; `bun test test/hall.test.ts test/whimsy-file.test.ts`: 35 pass, 0 fail.

Not done here: the other leakers named in the ticket (menard-format-*.log, srt-mux-*.sock,
needs-*/maintain-quiet-*.json) are not office tests; they stay open for their own tickets.
