APPROVE. Right then.

pool.test.ts seats two actors directly on the games tile's real pool spots instead of stepping up to 40k times until two wandered there. The rest are parked off-screen with `moving = true`, the same idiom as together.test.ts:19. `peopleAt` requires `spot.kind === kind && !moving && !path.length`, and the seating sets exactly those, so the `toBe(2)` precondition is deterministic. The `tick % 60` assertions are untouched.

Verified: `bun test test/pool.test.ts` passes (1 pass, 0 fail, 121ms). I did not run the full office suite. The office:check red on #724 (rack-card flake), as noted in pr.md, is outside this diff.

Nit, no block: the seat line pokes private actor fields through `any`. That is fine in a test, and together.test.ts does the same.