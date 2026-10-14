# Meteor: the puff and crater land in the street seen through the window

Closes ticket #348 (follow-up from #255, raised by nolan).

**What changed.** The meteor's streak ends at the window pane's bottom-left, but its puff and
crater were drawn at `doorX - 60` on the hall floor — indoors, and the wide room has no street in
view. `propsAt("meteor")` now places both where the streak stops, inside the pane (`windowX + 8`,
y 35): the street outside is the one seen through the glass, so the spec and the design's "lands
in the street with a puff of smoke" hold without inventing a street the room doesn't have. The
crater grows 5x3 → 9x3 and the puff 7x4 so they read at a glance (the ticket's "easy to miss");
both still fit the pane's left half. No server work; `office/kit/events.ts`, `office/kit/zoo.ts`
and one test.

**Decision.** The ticket asked whether the crater moves or the spec changes: the crater moves,
the spec stands.

**How I checked it.** Test-first: a new `events.test.ts` case pins the puff at t=150 and the
crater at t=300 to the window pane; it failed red at (540, 190) before the change. Then, from
`office/`: `bun run typecheck` (clean) and `bun test --timeout 60000` — 559 tests across 74 files,
0 fail (golden frames unchanged: no event runs in them). The `--timeout` is needed on a loaded box
because `bunfig.toml`'s `[test] timeout` is not honored by bun 1.3.14 — filed as ticket #352.
