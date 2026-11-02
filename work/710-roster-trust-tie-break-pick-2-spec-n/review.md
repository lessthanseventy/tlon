APPROVE — #710 re-review of 7e98894..562b725 (tzinacan)

I read the diff only and did not run the suite. The gate claim in pr.md is the builder's, not mine.

- `escalate` builds its candidates with `with_trust/1` (workline.ex:1424). That function rescues a raising lookup, logs a warning and returns the candidate without trust, so a failed trust store still escalates. The raising-lookup test asserts that, and that the post states no record.
- The post appends "(landed N of their last M builds first time)" only when the winner has a trust map. The tie test (junior daneri, senior zelda with 2 of 2) asserts the exact text and that zelda is picked.
- The neutrality test puts a worst record listed first against a zero record and against no record. Both orderings pick the neutral seat, which closes my earlier gap.
- The `pick/2` spec names the optional `trust` key.

No blocking findings.