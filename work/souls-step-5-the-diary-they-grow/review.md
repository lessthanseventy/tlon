verdict: approve

# Blocking — resolved

## The weekly job re-writes last week's landings (duplicate diary entries across weeks)

Fixed on the branch by ec4141f. `Diary.unwritten/2` drops entries dated on or before the seat's
newest diary line — the per-seat watermark the plan (T5, decision 1) specified. The job now calls
`Diary.write(seat, Diary.unwritten(seat, items), today)`, so a landing already written last Monday
(date ≤ watermark) is rejected and never gets a second line the next Monday.

The watermark extraction is refactored into `written_through/1`, now the single source shared by
both `due?/2` and `unwritten/2` — `due?`'s behavior is unchanged (nil → true; date →
`Date.diff(today, written) >= @spacing`), just no longer duplicated. Clean.

`write(_name, [], _today)` short-circuits to `:ok`, so once `unwritten` filters a seat down to
nothing the file is untouched — the cross-week case writes no line at all, not an empty one.

New test "a landing written in last week's run is not written again the next Monday" is
deterministic and meaningful: `generator_cmd` is `/nonexistent` so the model path returns `nil`
and the dated fallback is used; the landing's date (today−7) equals the pre-written diary line's
date, so `unwritten` drops it and the pre-existing line is the only one. Reverting the one job
line appends a second fallback line → `[_only]` fails. RED→GREEN confirmed by the verify round,
and the full gate passed on the branch (1776 tests, 0 failures, recorded check_passed).

No new findings in the diff — it is three lines of logic, a shared helper, a moduledoc update and
one test, all tracing to the blocking finding.

# Follow-ups (non-blocking, still open)

- **`append_diary/2` is not an atomic write.** A thread decision called for temp-and-rename; the
  impl uses `File.write/2` directly. A crash or disk-fill mid-write could truncate an
  operator-edited soul. Low odds (weekly 06:00) but the file is precious; the fix is write-to-tmp
  + `File.rename`.

- **`diary/1` doesn't filter to `- ` entries** as the plan spec'd. It returns every non-blank line
  in the section. Harmless today (only `- ` lines are ever appended) but `due?`/`unwritten`'s
  `written_through` and `diary_tail` would pick up a stray non-entry line if one ever lands there.

- **Bounce entries carry no reviewer, and the source the plan assumed isn't there.** The plan's
  history shape was `%{kind: :bounced, by: "lonnrot", ...}` premised on the event detail's
  `bounced` being "sent back by <seat>: …". It is not — `move_back/4` writes
  `detail["bounced"] = why`, a free-text reason with no seat. So the diary can only say "sent back
  on X"; attributing the reviewer needs a different source (the review that bounced it), not
  plucking `by` from the detail.

# Spec compliance (carried from the first review, unchanged by this diff)

- Presentation-only invariant holds: the callers guard covers `diary`/`append_diary`, `diary.ex`
  is the only new soul reader, the job calls `Diary` not `Soul`, and `tone/1` stays Diary-free. ✓
- `voice/1` carries the last two diary lines; banter test updated; `tone/1` unchanged. ✓
- No soul is ever created by the writer (`append_diary` → `{:error, :no_soul}`, job skips). ✓
- Untrusted model line is neutralised: only `- `-prefixed lines kept, re-wrapped, sliced, no
  embedded newlines → can't forge a `## ` heading. ✓
- Out-of-scope items (facts-per-seat, QA-as-own-source) named in the PR. ✓
- `insert_diary` preserves a section after Diary. ✓