---
name: verify-with-evidence
description: Use before claiming anything works, passed, or is done on a funes thread — run the REAL command (through cap), then record_check with its actual exit code so the proof is measured, not self-reported. A green claim with no check behind it is exactly the failure this whole stack was built against.
---

# Verify with evidence, never self-report

"It works." "Tests pass." "Done." — a claim that something works is backed by having
**run it**, or it is worth nothing. This stack exists because that claim, made without
running the command, was wrong over and over. So the discipline is simple and absolute:
**run the real thing, then record the measured result.**

## What to do

- **Run the actual command — through `cap`.** `mise run cap -- <cmd>` (or `scripts/cap.sh
  <cmd>`) runs it ONCE, captures the full output, and gives you the exit code and a
  distilled tail. Not a paraphrase, not "should pass" — the command, once, for real.
- **`record_check(cmd, exit, tail)` with what actually happened.** Pass the exact command,
  its REAL exit code, and a short tail of output. funes lands a `check_passed` (exit 0) or
  `check_failed` event — the kind is keyed on the number, so the brief shows the true
  verification state to whoever reads it next. This is the honest core: the outcome is
  measured at record time, never asserted.
- **On green, then `record_done` (and `complete_todo`).** A passing check is the evidence;
  `record_done(text, evidence)` is where you say what shipped, citing that check.
- **On red, say so — `raise_issue` or post it.** A `check_failed` is not a failure to hide;
  it is the thread telling its successor where the work actually stands. Surface it.

## What NOT to do

- **Don't record a check you didn't run.** A fabricated `check_passed` is worse than no
  check — it launders a guess into apparent proof, the exact defect the axis exists to kill.
- **Don't report done off a stale memory of green.** If you changed code after the last
  check, the last check is about the old code. Re-run.
- **Don't confuse record_check with record_done.** `record_check` is "I ran it, here's the
  exit code" (measured, mechanical). `record_done` is "this shipped" (a judgement). Both
  land in the brief; use each for what it is.

The test: could a successor, reading only the thread's CHECKS, trust that what you said
works actually does — because the exit code is right there, keyed on the number you didn't
get to choose?
