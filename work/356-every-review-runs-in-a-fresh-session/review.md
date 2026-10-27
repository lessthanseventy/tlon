APPROVE — note: no free reviewer was at the builder's grade (greybeard); reviewed by tzinacan, read-only, diff only. I did not run the gate or the tests (sandbox); the builder's red→green and `menard run check --in server` claims in pr.md are unverified by me — verify/landing runs the real gate.

Read: origin/main...HEAD (8 commits, 14 files).

Correct:
- `Staffing.end_review/1` mirrors `roll_leaf/1`'s guard (tmux fault ⇒ leave sessions alone, no stranded window) and skips `pane_retired`, as pr.md says.
- `Workline.record_verdict` ends the session after the verdict is durable and before `bounce`, so the request_changes builder respawn is not killed by it. The approve path's later QA close is a harmless double close.
- `BranchReview.record` `with` rewrite: the added `{:error, why}` clause is needed (else a failed `record_event` double-wraps); ends the session only on `{:ok, event}`; a verdict off any thread ends nothing.
- `Board.brief/2`: `reviewing?` needs stage "review" AND viewer == lead, so the operator API (`brief/1`) and the builder keep the conversation; `hidden_if` keeps counts. `last_reviewed` stays in the stage brief; tested.
- Lobby refusal uses `Channel.standing?/1` (exists); the test asserts nothing is recorded.

Follow-ups (non-blocking):
1. Spec decision 2 says no thread posts in a review brief; `reviewing?` covers only a workline at stage review. A `review_branch` thread (e.g. "review and land PR") still shows OPENING/RECENT/DONE/LEARNINGS. Plan task 2 named it; the code and pr.md narrowed it silently. Extend or amend the spec.
2. Hiding OPENING removes the operator's original ask from the reviewer; it must come from spec.md.
3. `end_review` ends ALL live sessions on the thread, not just the verdict author's; a `review_branch` verdict from a shared non-standing thread would end other agents' sessions.
4. `review_branch` over MCP is tested only for the refusal; the success path ending the session is covered only via `BranchReview.record` directly.