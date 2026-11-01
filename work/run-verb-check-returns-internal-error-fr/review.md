No free reviewer is at the builder's grade (greybeard); reviewed by tzinacan (sonnet-5-5), one grade down.

APPROVE. Read the full diff against main.

- `Server.Source.Tools.run/4` gets a head clause for `:check` that returns `{:error, msg}` pointing at `run_task`. The `test`, `format` and `compile` clause is unchanged and its guard is narrowed correctly. The only caller is `RunVerb` (mcp/tools/source.ex:132), and it already handles `{:error, _}`.
- The `check` value stays in the tool's enum on purpose. Without it the client would get a schema error and never see the pointer.
- The new test covers the refusal and also asserts that `compile` still works. The pr.md reports a red-then-green run (16 tests, 0 failures). I did not re-run it.
- The moduledoc, the `@doc` and the root AGENTS.md sentence all match the new behaviour.
- AGENTS.md is touched, which counts as a limit. The change is a one-sentence accuracy fix, so I approve it, and the merge gate and operator still see it.

Not verified: I did not run `server:check`. pr.md says it goes through `run_task`; the merge gate runs the full gate anyway.

Non-blocking: the message's "(or "check")" points at the full queued gate, which is the heavier option. That is fine.