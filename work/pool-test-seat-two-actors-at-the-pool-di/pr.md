pool.test: seat two actors on the real pool spots, not a 40k-step warm-up (#619)

The "a pool shot is in someone's hands" test warmed the room up to 40,000 steps
until two actors happened to wander to the pool. Seed 11 found two; another seed
hit the cap and failed. Now two actors are seated directly on the games tile's
two real pool spots, and the rest are parked off-screen as together.test does.
The `tick % 60` aim/roll assertions are unchanged. One file changed.

Closes #619.

Checked: `bun test office/test/pool.test.ts` alone, 589ms before, 70–130ms after (3 runs).
`office:check` is red on #724 (rack-card.test.ts "a node with no job queue reads
neutral under all green", a full-suite load flake, not touched here).
