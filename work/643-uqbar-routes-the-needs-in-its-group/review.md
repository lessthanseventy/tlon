# Review — #643 Uqbar routes the needs in its group

**Verdict: approve.** Branch `work/643-uqbar-routes-the-needs-in-its-group` at deee7de (code at 8b1435f). Three legs of the ticket are on the branch and each is test-first; the server's verify ran `mise run check` green (2137 server tests, 0 failed).

## What I checked, against the ticket and plan

1. **Inbox carries key + route** (`operator_inbox.ex`). Renders from `Needs.grouped/1`, uqbar group first, settled omitted. The witness: `for(group <- ~w(uqbar phone machine clipboard)a, n <- g[group], do: render(n))` — all four of grouped's non-settled groups, so nothing `list/0` showed is lost except settled items, which the digest holds. Test proves key and `route: uqbar` on a fresh question and absence after `Needs.settle/3`.
2. **The role names the loop** (`profiles.ex`). THE INBOX LOOP: operator_inbox → settle_need / pass_up_need per item, with why and recommendation; seats, quota and tool_denied named as never Uqbar's, which matches `pass_up_rule/1`'s `:always` clauses at needs.ex:185-186. The 30-minute fail-open is stated, not changed. The dropped "settle stale items" clause is covered by "route each one, do not skip".
3. **The debounced wake** (`needs_page.ex`, from `Drain` every minute). "Paged" is a `tlon` post on the study with `payload["need_page"]` no older than the item; no migration, survives a restart. One post per workspace per pass; skipped while `Thinking.thinking_for(study.id)` is non-empty and within 300 s of the last page, and both skips only delay. I confirmed the wake actually fires: `Channel.post` broadcasts `:message_posted`, the switchboard wakes a thread's lead on a plain post and a mentioned coworker on `@uqbar`, and `Outside.study/1` opens the study with `agent_id` = uqbar, so both paths hit the same pane. The seconds-grain compare in `paged?` is right: `Message.post_changeset` truncates `created_at` to seconds (message.ex:64), so an item's microsecond `at` in the same second would otherwise read as newer than its own page and re-page forever.
4. **Fail-open and knob untouched.** `route_item/4` and `uqbar_route_minutes` are not in the diff. Nothing on the branch writes `need_routing`.
5. **Security.** The inbox stays read-only; the page is a machine-scope post by `tlon`. No new input reaches a shell.

## Open, not blocking

See follow-ups: Drain ordering (a raise in `NeedsPage.run/1` would skip the minute's redelivery and drain), and the per-minute cost of `Needs.grouped/1` while `uqbar_routing` is off.

Task 4 (the live check: a fresh conditional need pages the study and gets a `need_routing` row inside 30 min) is owed after landing and a release cut, as the plan says; it is not evidence this review can claim.