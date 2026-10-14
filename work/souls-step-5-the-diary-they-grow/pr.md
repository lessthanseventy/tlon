Souls step 5, the diary: a builder's soul gets a dated line for what it shipped and what was sent back, written weekly, and the next week's voice reads the last two.

**What changed**
- `Server.Soul.diary/1` and `append_diary/2`: entries land at the end of `## Diary`; every other byte of the soul is kept, and a missing heading is added. Never creates a soul.
- `voice/1` carries the last two diary lines as `lately:`. `tone/1` stays Diary-free.
- `Server.Diary.history/2`: per builder seat, its landed worklines (a `work_landed` on a thread it posted on) and the send-backs of its threads, from real rows only.
- `Server.Diary.write/3`: the model writes up to three in-voice lines when it is available; otherwise one dated line per item. No soul, no file.
- `Server.Jobs.Diary`, cron Monday 06:00: writes each builder's week, skipping a seat whose newest line is under six days old, so a retry never writes a week twice.
- `soul_callers_test` now also guards `Soul.diary`/`append_diary`; only `server/diary.ex` may touch them.
- Banter test: the diary reaches the scene as its last two lines; Fears still never do (the design §4 has the next week's voice read the diary).

**Ticket:** #64 (souls step 5).

**Not in this slice (file as follow-ups):** facts banked per seat (facts carry no seat author); QA verdicts are covered only as send-backs; the office card does not yet render the new lines beyond what `souls.ts` already shows; diary compaction after months.

**How it was checked**
- Each task red first: the new tests failed with the expected undefined-function or wrong-output errors before the code existed. The voice and banter tests failed on the old output.
- `menard run check --in server`: 1775 tests, 0 failures.
- `mise run check:names`: ok.
- Diary job tests cover the ticket's check: after a merged workline its builder's diary mentions it, once across re-runs.
