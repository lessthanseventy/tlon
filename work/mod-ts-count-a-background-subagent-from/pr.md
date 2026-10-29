mod.ts: count a background subagent from agent.spawn, not turn.start

The host raises no `turn.start` for a subagent (its input has no agentId), so `running` stayed empty and a seat went idle the moment its main turn ended. `agent.spawn` now adds the started agent's `agentId` (guarded: absent for remote/isolated agents or a refused spawn) on both the plain and Explore→haiku paths; `turn.start` keeps only `mainEnded = false` and the thinking declare.

Closes #546.

Checked: mod tests rewritten to spawn → main turn.complete (no presence_idle) → `turn.complete({agentId})` (presence_idle), red before the change (2 fail), green after; `mise run adapters:claude-code:mod` 48 pass, `adapters:claude-code:check` 90 pass. The live proof (240s background Agent, glances at +45/137/215s) is owed after land, release cut and a rolled pane.
