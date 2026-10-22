Approve.

#516 — sandboxed seat allow list names menard's plugin tools

The change swaps one stale token in `adapters/claude-code/launch.sh`: the sandboxed seat's `permissions.allow` listed `mcp__menard`, but menard's tools are served as `mcp__plugin_menard_menard__*` (plugin-loaded), so every menard edit/run in a `dontAsk` seat was refused without a prompt. The fix replaces it with `mcp__plugin_menard_menard`.

## Verified

- **Prefix is correct.** menard's tools read `mcp__plugin_menard_menard__*` — confirmed against this session's own tool names and `server/deps/menard/CHANGELOG.md` ("The tools are `mcp__plugin_menard_menard__<tool>`"). The allow entry `mcp__plugin_menard_menard` prefix-matches all of them, the same way `mcp__tlon` matches `mcp__tlon__*`.
- **Scope is correct.** The neighbouring entries `mcp__tlon`, `mcp__lsp`, `mcp__tlon-citizen` stay unprefixed — those are plain MCP servers (tlon/lsp are declared in `mcp_json`; tlon-citizen registers without the `plugin_` prefix), not plugin-loaded, so they were never stale. Only menard was wrong.
- **Test guards the fix.** `lib/launch.test.ts` runs the launcher in `TLON_LAUNCH_DRYRUN=1`, parses the printed `settings:` line, and asserts `permissions.allow` contains `mcp__plugin_menard_menard`. With the old `mcp__menard` token that assertion fails, so the test is a real regression guard, not a tautology.
- **Gate green.** `mise run adapters:claude-code:check` → 85 pass / 0 fail across 8 files (frozen install, typecheck, bun test).
- **Surgical.** One token in launch.sh + one new test file + `pr.md` in the conventional `work/<slug>/` location. No adjacent churn.

## Follow-up (non-blocking)

The plugin-naming asymmetry — menard tools carry the `plugin_<dir>_<server>` prefix while tlon-citizen's do not — is a property of how each plugin registers, not a defect here, but it's the kind of thing that will bite the next person who addlists a plugin tool by guess. Worth a one-line note in `adapters/claude-code/AGENTS.md` near the allow list if someone touches it.