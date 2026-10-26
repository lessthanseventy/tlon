Verdict: approve. No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (deepseek-flash). Weigh accordingly.

Re-review after 7c6036b (prefix moved into `Brief.parked_prefix/2`). Diff read, not run by me; verify owns the gate.

- `gate_message/2` builds on `parked_prefix(slug, stage)`; the text is unchanged. `Needs.gated_at/1` matches `prefix <> "%"`, latest by id, author "tlon", falling back to thread created_at.
- Tests cover both directions (hour-old workline that just parked stays with Uqbar; park older than uqbar_route_minutes fails open), plus a Brief test pinning the shared prefix.
- Nit, non-blocking: `_`/`%` in a slug act as LIKE wildcards; it can only widen the match to a near-identical notice, so harmless.