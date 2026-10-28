# Review — rule-of-1-parses-the-bash-command-out-of @ b275b40

**Verdict: request_changes** — one line, in the change's own blast radius.

The change itself is right: `tool_denied` grows a `command` field (denied.ex), the mod fills it only when `summaryOf` left the command untouched (doing.ts `commandOf`: no redaction, no `⏎` join, no cut, no cwd-relativising), and `rule_of/1` reads the field instead of splitting `"Bash · "`. Tests on both sides go red first (needs_test summary-only → `rule: nil`; mod.test expects `command`). Verify's `mise run check` is exit 0 on the branch; I re-ran `bun test lib` myself: 90 pass, 0 fail.

## Findings

1. **The smoke fixture now drops the very verb this ticket exists to protect.** `server/lib/server/smoke/fixtures.ex:239` seeds the `tool_denied_need` events summary-only:
   ```
   detail: %{"agent" => "fixture", "tool" => "Bash", "summary" => "Bash · echo hi", "reason" => "fixture"}
   ```
   After this diff `rule_of/1` returns nil for it, so the smoke's card loses "Allowed it: Bash(echo hi)" (alerts.ex `actions/1` emits nothing when `rule` is nil; tui `main.ts:867` hides the `A` key). That is the exact failure #492 names — a contract change in one place quietly dropping a verb elsewhere — reproduced inside the same diff. Fix is one line:
   ```
   server/lib/server/smoke/fixtures.ex
   -          detail: %{"agent" => "fixture", "tool" => "Bash", "summary" => "Bash · echo hi", "reason" => "fixture"}
   +          detail: %{"agent" => "fixture", "tool" => "Bash", "summary" => "Bash · echo hi", "command" => "echo hi", "reason" => "fixture"}
   ```
   Worth a grep for any other seeded `tool_denied` detail; I found only this one outside tests.

## Non-blocking

2. `mod.ts:651` computes `commandOf(...)` for every `tool.check`, allowed calls included, before the `deny` test. Harmless (one extra `summaryOf`), but it belongs inside the `if` with the rest of the declare.

3. Noted as a gain, not a finding: dropping the `…` guard also ends a latent wrong rule. A command invoked by absolute path under cwd used to summarise relative (`Bash · scripts/x.sh`) and so offered `Bash(scripts/x.sh)`, which would never match the real call; `commandOf` now refuses that case outright.

No `bench_contrast` row in CHECKS; nothing to say there.