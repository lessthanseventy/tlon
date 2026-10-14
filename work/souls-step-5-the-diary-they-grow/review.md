verdict: request_changes

# Blocking

## The weekly job re-writes last week's landings → duplicate diary entries across weeks

`Server.Jobs.Diary.perform/1` always sets `since = today - 7 days` and relies on `Diary.due?/2`
(the 6-day guard) alone for idempotency. `due?` only blocks **same-week** retries (a re-run within
6 days); it does not block the next Monday's run, which is always 7 days on (7 ≥ 6 → due passes).
So every Monday, `history(ws, today-7)` re-includes any landing from the prior 7 days — including
landings already written last Monday. A workline that lands once gets a diary line this Monday **and
again next Monday** (different date prefix, same "shipped X"). Each landing is mentioned twice; the
watermark never advances past the event.

The plan (T5, decision 1) specified `since = newest diary date OR 7 days ago` — the diary's newest
date is the watermark ("written through"), so already-written landings (at ≤ watermark) are excluded.
The build replaced watermark-`since` with a fixed 7-day window and kept only the due-gate, defeating
the watermark design the plan committed to.

Repro not covered by the current test: seed a soul with a diary line dated 8 days ago + a
`work_landed` event 7 days ago on a thread daneri posted on, today = Monday → `perform` writes a
line; advance today 7 days → `perform` writes the same landing again. The job test
("once across re-runs") only re-runs same-day, where `due?` blocks, so the cross-week duplicate is
uncaught.

Fix (matches the plan): use each seat's watermark as the history cutoff. Minimal shape — keep
`history/2`'s 7-day candidate window, then drop items whose `Date.new!(item.at) <= watermark_date`
for that seat, where `watermark_date` is the date on `Soul.diary(seat) |> List.last()` (the same line
`due?` already inspects). Add a cross-week test that advances the date 7 days and asserts no
duplicate line for the same landing.

# Follow-ups (non-blocking)

- **`append_diary/2` is not an atomic write.** A thread decision called for temp-and-rename; the
  impl uses `File.write/2` directly. A crash or disk-fill mid-write could truncate an
  operator-edited soul. Low odds (weekly 06:00) but the file is precious; the fix is write-to-tmp +
  `File.rename`.
- **`diary/1` doesn't filter to `- ` entries** as the plan spec'd. It returns every non-blank line
  in the section. Harmless today (only `- ` lines are ever appended) but `due?` and `diary_tail`
  would pick up a stray non-entry line if one ever lands there.
- **Bounce entries carry no reviewer, and the source the plan assumed isn't there.** The plan's
  history shape was `%{kind: :bounced, by: "lonnrot", ...}` premised on the event detail's `bounced`
  being "sent back by <seat>: …". It is not — `move_back/4` writes `detail["bounced"] = why`, a
  free-text reason with no seat. So the diary can only say "sent back on X", and attributing the
  reviewer needs a different source (the review that bounced it), not just plucking `by` from the
  detail.

# Spec compliance (what's right)

- Presentation-only invariant holds: the callers guard now covers `diary`/`append_diary`, `diary.ex`
  is the only new soul reader, the job calls `Diary` not `Soul`, and `tone/1` stays Diary-free. ✓
- `voice/1` carries the last two diary lines; banter test updated to match; `tone/1` unchanged. ✓
- No soul is ever created by the writer (`append_diary` → `{:error, :no_soul}`, job skips). ✓
- Untrusted model line is neutralised: only `- `-prefixed lines kept, re-wrapped as
  `- <date>: <text>`, sliced, no embedded newlines → can't forge a `## ` heading. ✓
- Out-of-scope items (facts-per-seat, QA-as-own-source) named in the PR. ✓
- `insert_diary` correctly preserves a section after Diary (tested). ✓