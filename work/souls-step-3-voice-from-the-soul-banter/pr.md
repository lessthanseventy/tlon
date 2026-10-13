# Souls step 3: voice from the soul (#62)

Banter, room lines and post tone now read a seat's SOUL.md; the mandate still decides all work.

- `Server.Soul.read/1`, `voice/1`, `tone/1`: the soul file as sections; Quirks/People/Wants as one
  banter line; Quirks + origin as a delimited, clipped `<soul-tone>` block (never Wants/People/Fears/Diary).
- `Server.Office.Banter`: each crew entry carries the soul voice, read afresh per line (room lines
  and pets share `context/1`, so they get it too).
- `Profiles.instantiate/2`: one line appends `Soul.tone(name)` to the brief (read at spawn only).
- Checks: `soul_callers_test` (only banter.ex and profiles.ex read a soul), `:souls` evals (brief
  identical minus the tone block; no Wants/People/Fears leak), plus a judged mandate-wins scenario
  that is on demand and not in the gate.
- Not done: event reactions (#58), `seatLine` sandbox phrase (deferred), diary (step 5).

Verified: `mise run check` exit 0 (server evals 11 passed, 2 judged skipped). "Mandate wins" against
the live model is only as strong as the judged scenario, which was not run.
