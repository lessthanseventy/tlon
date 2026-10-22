# Review — Uqbar routing (#578, #579)

**Reviewer:** runeberg (glm-5.2). No free reviewer was at the builder's grade (greybeard), so this review is from a different grade — read with that in mind.

**Verdict: APPROVE.**

The change is sound and well-tested. I ran the changed suites independently: 243 server tests (needs, mcp server, gateway, alerts, flags, doctor) and 29 office tests (needs-surfaces, surfaces, keys) green. The red-first coverage matches the spec's "Done when" list, including the review amendments (fail-open, hook refusals conditional, #579 handoff-as-post). The flag ships off, so the merge changes nothing until the operator flips it.

## What I verified
- `pass_up_rule/1` clause ordering: a hook's `tool_denied` (hook: true) hits the `{:when, @narrow}` clause before the bare-kind `:always` clause; a permission refusal (hook false/absent) falls through to `:always`. The bare-string form still returns `:always`. Correct.
- Fail-open: `expired = now - uqbar_route_minutes`; `route == "uqbar"` and `item.at` at or before `expired` → `pass_up` with "Uqbar did not route it in time". A verdict (settled/passed_up) wins over the timeout. Correct.
- Flag off: `verdict_row` returns `@no_verdict`, no row is read and every conditional kind routes `pass_up` — #326's behaviour. The test with a settled row present confirms it.
- Settled/overrule lifecycle: settle → leaves every surface, in the 24h digest; overrule deletes the settled row → item back in `uqbar`; `not_settled` on a passed_up key or a second overrule. Correct.
- Seat-only gate: `record/3`'s `by != "uqbar"` guard → `:forbidden`; a nil handle fails it too. The MCP tool test confirms a coworker's call records nothing.
- `need.hook` dot access in `alerts.ex:177` is safe — every `tool_denied` item from `Needs.list()` carries `hook` (set in `tool_denied/2`). The guard `rule when is_nil(rule) or need.hook` correctly suppresses "Allowed it" for hook refusals and nil rules.
- Key table: dual `u` (tool_denied + settled) shares one verb "hand to Uqbar" — passes keys.test.ts (one meaning per key).

## Follow-ups (non-blocking)
1. Dangling JSDoc in `office/tui/data.ts`: `refusalToUqbar` was inserted between `allowed`'s doc comment and `allowed` itself, so the "the refused command's allow rule… wakes the lead" comment now floats above `refusalToUqbar`'s own doc and `allowed` has lost its (load-bearing) doc. Move the allow-rule comment back to sit directly above `export const allowed`.
2. `hook_refusal?/1` string match is fragile: the one tell is matching `"PreToolUse:" <> _` in the event `reason`. The plan accepted this (no adapter `source` field) and it's documented, but a wording change in Claude Code silently re-classifies hook refusals as permission refusals (which then ring the phone and refuse a verdict). The adapter `source` field on #581 is the real fix; keep the string match's doc current until it lands.