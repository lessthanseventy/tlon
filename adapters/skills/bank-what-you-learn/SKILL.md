---
name: bank-what-you-learn
description: Use when you've learned something durable on a funes thread — bank it as a fact with the right provenance. A reproducible finding carries the command that re-runs it; a hunch is banked AS a hunch; the operator's words are banked only by quoting him. Never dress a guess in a certainty it hasn't earned.
---

# Bank what you learn

funes ranks facts by how surely they can be believed, and the ranking only works if you
bank honestly. The order, read at query time, is:

> **stated** (the operator's own words) > **checked** (derived, with a command that re-runs
> it) > **hunch** (derived, unverifiable)

Your job is to put each thing you learned at the rank it actually earns — no higher.

## The rules

- **A reproducible finding is a fact WITH its `check_cmd`.** If a claim can be re-run — a
  test, a query, a command — bank it with that command:
  `bank_fact(kind: "learned", text: "...", check_cmd: "mix test path/to_test.exs")`. The
  command is what lets a later reader (or a later you) re-verify instead of trusting.
- **A hunch is a derived fact WITHOUT a `check_cmd`, and that is fine — say so.**
  `bank_fact(kind: "learned", text: "the flicker is probably the double repaint")` banks an
  opinion, and funes will render it and rank it AS an opinion. A hunch banked as a hunch is
  useful. A hunch banked as truth is a lie that compounds.
- **Never dress a guess in a check it doesn't have.** Don't attach a `check_cmd` that
  doesn't actually verify the claim to make a hunch look solid. The check must re-run *this*
  claim, or it must not be there.
- **The operator's words are `stated` — and reachable only by quoting him.** You cannot type
  a `stated` fact. When the operator states a constraint, correction, or preference on the
  thread, bank it from his own message: `bank_fact(kind: "constraint", from_message: <his
  message id>)`, which quotes him verbatim. Your paraphrase of him is never a stated fact —
  that is the one abuse the ranking exists to prevent.
- **`kind` is what kind of claim, not how sure you are:** `decision | constraint | learned`.
  Certainty is not a kind — it comes from provenance and the check, above.
- **One fact, one claim.** If you learned two things, bank two facts. A paragraph with three
  findings cannot be ranked, superseded, or re-verified as a unit.

## Before you build on someone else's fact

If a fact you're relying on is a **hunch** (derived, no check), re-verify it before you
build on it — don't inherit an unchecked guess as ground truth. If you can produce the
command that settles it, bank a new, checked fact; if the operator has since settled it,
his stated word supersedes yours.

## When it's not a fact

- A knowledge gap in the work ("does raxol support embedding?") is a **question**, not a
  fact — for now, post it on the thread. (A dedicated question type is coming; until then the
  thread is its home.)
- A defect in the stack itself ("the termbox NIF crashes on resize") is an **issue** —
  `raise_issue(summary, evidence)`. That is the machine's own tracker, never product work.
- Being stuck waiting on the human is a **message**, never an issue and never a fact.
