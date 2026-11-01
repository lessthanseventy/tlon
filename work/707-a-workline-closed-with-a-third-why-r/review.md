# Review — workline 707, branch work/707-a-workline-closed-with-a-third-why-r @ f3a2108

**Verdict: approve.**

The change does what ticket #707 and tertius's brief (#27936) asked: a third why, `resolved`, closes an unmerged workline and marks its ticket **done** with "Resolved without code in workline #N: why" appended, instead of `abandoned`'s trip back to intake. The diff is 75 lines across the five doors the brief named plus two RED→GREEN tests; nothing outside the ask.

## What I checked

1. **`Channel.close_as/2`** (`server/lib/server/channel.ex:112`) admits `:resolved` in the same guard as the other two, and the blank-trim refusal covers it — the test sends `{:resolved, "  "}` and gets `{:error, :why_closed}`. The "✕ closed unmerged" post now says `resolved without code: <why>`; the `case` replaces an `if` that would have mislabelled a third kind as abandoned.
2. **`Tickets.closed_unmerged/3`** (`tickets.ex:197`): `:resolved -> {"done", …}`. Nothing else in `server/lib` matches on the kind atom (grepped `:superseded`/`:abandoned`; the other hits are the recall engine's unrelated `"superseded"` event kind). So no reader is left with an unhandled clause.
3. **The doors** build the tuple consistently, precedence `superseded_by` > `resolved` > `abandoned` in all three (`thread.ex:506-508`, `coordination.ex:321-323`, `operator_api.ex:543-545`). `tlon-cli close-thread` validates `resolved` in its `case` before interpolating it into the rpc. Every "say why it closes" string names the three.
4. **Tests.** Both new tests green when I ran them (`menard run test --in server test/server/tickets_test.exs:156` and `…/mcp/server_test.exs:1686`, each `{"ok":true,"tests":1,"failed":0}`). The server's own verify ran `mise run check` on f3a2108: exit 0 (CHECKS row 18:26:08). No `bench_contrast` row — no persona file touched, none expected.
5. **No AGENTS.md, spec or glossary line** lists the two doors (grepped `superseded_by` across `*.md` outside `work/`), so no operator-gating doc was touched. emma's note (#27945) matches.

## Not blocking, noted below as follow-ups

- The office's own close keys still send only `abandoned` or nothing, so the operator's door can't say `resolved` yet.
- One docstring in `worktree.ex` still lists two kinds.
