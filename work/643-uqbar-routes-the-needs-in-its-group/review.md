# Review — #643 Uqbar routes the needs in its group (round 2)

**Verdict: approve.** Branch `work/643-uqbar-routes-the-needs-in-its-group` at 7b79d1d. One code commit since my 8d1b117 verdict; it closes QA's finding and both of my follow-ups, each with the code I read, not the message I was told. The server's verify ran `mise run check` green on this head (12:06Z).

## What changed since 8d1b117, checked line by line

1. **Uqbar can call the inbox.** `profiles.ex:1059`: `@uqbar_mcp update_in(@tlon_mcp, ["tlon", "excludeTools"], &(&1 -- ["operator_inbox"]))`, the same shape `@sheriff_mcp` uses at :358, and `@citizens["uqbar"].mcp` now reads `@uqbar_mcp`. The witness: `profiles_test.exs:494` refutes `operator_inbox`, `settle_need` and `pass_up_need` in `citizen_profile("uqbar", 7).mcp["tlon"]["excludeTools"]`. That is QA's finding (nolan, #13677) closed, and the test that would have caught it.
2. **Drain delivers before it pages.** `drain.ex:15-18`: `report_overdue` → `redeliver_unheard` → `drain` → `NeedsPage.run`. A raise in the needs scan now costs that minute's page, never its delivery. My follow-up 1.
3. **No scan while routing is off.** `needs_page.ex:21`: `if Server.OperatorConfig.setting("uqbar_routing")` guards the whole `Needs.grouped/1` pipeline, else `:ok`. It is the same reader Needs itself uses at needs.ex:1004, so the two can't disagree. `needs_page_test.exs:108` (routing off: nothing paged, no study opened) still holds against the guarded path, and the setup at :17 puts the setting on for the rest. My follow-up 2.

Nothing else in the diff: the inbox, the role prompt, the paging logic and the fail-open are as reviewed at 8d1b117.

## Still owed, not by this review

Task 4, the live check (a fresh conditional need pages the study and gets a `need_routing` row inside `uqbar_route_minutes`), waits on landing and a release cut, as the plan says.
