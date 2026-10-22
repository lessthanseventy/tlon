A sandboxed seat's allow list names menard's plugin tools.

**Why:** A coworker seat runs `dontAsk`, so any tool missing from `permissions.allow` is refused without a prompt. The list named `mcp__menard`, but menard's tools are served as `mcp__plugin_menard_menard__*`, so every menard edit and run in a seat was refused.

**What:** `adapters/claude-code/launch.sh` swaps `mcp__menard` for `mcp__plugin_menard_menard` in the allow list. `lib/launch.test.ts` now asserts the plugin prefix. 62f6461 in this branch added the test and the stale `mcp__menard`; 4abd928 supersedes that entry, so the branch's net change is the plugin prefix only.

**Closes:** #516.

**Checked:** `lib/launch.test.ts` went red on the old allow list (`mcp__menard`, no plugin prefix) and passes with the fix. `mise run adapters:claude-code:check` exit 0: install (frozen), typecheck, 85 tests across 8 files.

**Out of scope:** the worktree-start check belongs to #522/#336.
