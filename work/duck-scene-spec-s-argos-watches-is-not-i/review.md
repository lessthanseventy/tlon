# Review — duck-scene-spec-s-argos-watches-is-not-i

**Verdict: approve.**

One commit (71437da), docs-only: toy step 5's pr.md "Not done" line now names "Argos watching the duck (spec §Duck)" beside the zoo reactions and the monitor glow, deferring to step 7; plus this workline's own pr.md.

Checked against the repo, not the builder's word:
- `work/toy-step-5-the-events-zoo-meteor-fire-dr/spec.md:73` — the Duck bullet does say Argos watches.
- `office/kit/pets.ts:19` — `Dog.mode` is `"walk" | "sit" | "sleep"`; no watching mode exists, so "no fitting existing pet mode" is accurate.
- `office/kit/events.ts` — no Argos reference; the behaviour is indeed unimplemented.
- Ticket #306 offered implement-in-step-7 or name-as-skipped; this takes the second, which is the one the step-5 plan (plan.md:568) already prescribed for pet reactions.

No code, no tests, nothing to run. Commit attribution (Co-Authored-By / Tlon-Model) consistent.
