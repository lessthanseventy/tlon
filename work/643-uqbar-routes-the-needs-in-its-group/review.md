# Review — #643 Uqbar routes the needs in its group (round 3)

**Verdict: approve.** Branch `work/643-uqbar-routes-the-needs-in-its-group` at 2b16e45. One commit since my f7f1310 verdict, the operator's send-back on the role line; nothing else in the diff (`git diff f7f1310..HEAD -- . ':!work/643-…'` touches profiles.ex and profiles_test.exs only). The server's verify ran `mise run check` green on this head (12:41Z).

## What changed since f7f1310, checked against the code it describes

1. **The role now says what `pass_up_rule/1` does.** profiles.ex:570-573: "a permission refusal always reaches him … A tool_denied from a hook is routed: a hook's refusal is yours; tell the seat on its thread what the hook asks (usually the hook's own message), then settle it." The rule it quotes: needs.ex:185 `pass_up_rule(%{kind: "tool_denied", hook: true})` → `{:when, @narrow}`; :186 bare `tool_denied` → `:always`. They agree now; the old line ("tool_denied always reach him") contradicted :185.
2. **Uqbar can act on it.** The inbox gives it both halves: `route` tells a hook's refusal apart (a hook's routes `uqbar`, a permission one never does), and `text` carries the hook's own message, `tool_denied_text/2` at needs.ex:808-811 appends `detail["reason"]`, which for a hook is the `PreToolUse: …` line `hook_refusal?/1` keys on (:829). So "tell the seat what the hook asks" is readable from the item, not a guess.
3. **The witness.** profiles_test.exs:494: asserts "a hook's refusal is yours" and "a permission refusal always reaches him", refutes the old wording. emma reports it red before the edit, 69/0 after; verify's full check confirms.

Nit, not a finding: "Needs of kind seats and quota, and a permission refusal always reaches him, are never yours to route" has lost its grammar in the edit. A model reads it fine and the test pins the operator's exact phrase, so I leave it.

## Still owed, not by this review

Task 4, the live check (a fresh conditional need pages the study and gets a `need_routing` row inside `uqbar_route_minutes`), waits on landing and a release cut.
