APPROVE — whimsy: Argos fetches the newspaper

Scope: pure office/ change (pets.ts +1 line, wide.ts step() +4/-1, one test). No server/ touch, no new Dog field — matches the three locked decisions in spec.md.

Checked by reading the diff against spec.md/plan.md:
- ARGOS.paper: 3 canned lines, same shape as rally/muse, no {name}. As specced.
- step(): idle chance 1/2200, guarded by !dog.path.length, not asleep, and quiet(saidUntil) — never retargets a walking dog or talks over a balloon. Reuses dogDo("office"), then overwrites the line via dogSay(paper); dogDo/stepDog untouched.
- Test (red commit df50c38 precedes feat 19b002f) drives the room with chance≈1 and asserts mode "walk", said ∈ ARGOS.paper, and a balloon at the dog's x. Tests behavior, not just data.
- Gate: the brief's recorded checks show `mise run check` exit 0 on this branch. I did not re-run it myself.

Notes (non-blocking):
1. Deviation from plan: the muse chime became `else if` of the new branch (plan had two independent ifs). Better — one tick can't double-write `said`.
2. Lines say "morning"/"evening edition" with no day-gating — harmless, matches decision 2.
3. Not verified: live rendering in the office TUI (no drive-office run by me).
