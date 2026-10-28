APPROVE — 9c1515b, "Allowed-it body: fence a rule holding a backtick".

Read the diff only; I could not run the suites (menard's build dir is read-only in my seat). The gate on verify/landing is the proof.

- Both copies (`Server.Alerts.code_span/1`, `codeSpan` in office/tui/data.ts) do the same thing: a fence one backtick longer than the longest run, padded with a space when any backtick is present. CommonMark strips that one space pair, so a run at either end can't merge with the fence. A rule with no backtick renders as before.
- Each side has a test with the exact expected body.
- Lines are under the formatter's 120; no AGENTS.md or spec text goes stale.

Nit, not blocking: data.ts already had a stray doc comment above `refusalToUqbar` ("the refused command's allow rule…") that belongs on `allowed`. Pre-existing.