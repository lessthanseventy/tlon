APPROVE — 7b9cb5d (#87), Memory extractor refuses placeholder/too-short facts.

Scope: not already on main; one commit on the branch, touching only server/lib/server/memory/extractor.ex and a new server/test/server/memory_extractor_test.exs.

Fix: `junk?/1` rejects any fact with fewer than 8 letters/digits (`@min_alnum 8`), applied in `shape/1` before facts reach bank_fact. Covers "...", "…", blank, punctuation-only.

Test: asserts "...", "…", whitespace, "", "?!", "- . -", "ok" are refused and a real fact survives.

Verified: I read the diff only. I did not run the tests myself; the recorded `mise run check` passed at 05:40Z.

Non-blocking: 8 is a heuristic; a real 7-alnum fact such as "Use pnpm" is refused too. Lowering @min_alnum to ~5 would still catch every placeholder. Left as is.