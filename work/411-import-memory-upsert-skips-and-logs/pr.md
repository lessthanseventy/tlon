Import of a memory file the junk filter refuses now skips and logs it, instead of raising or overwriting.

**What changed.** `Fact.bank_changeset` refuses a placeholder (under 5 letters or digits), but `Server.Import.Memory` matched `{:ok, _}` on the insert, so one refused memory raised a `MatchError` and stopped the whole import. The update path wrote the raw text over an existing fact through a changeset that skips validation. A single `Fact.junk?` check now runs before either path: the memory is logged and dropped, the import continues, and an existing fact keeps its text.

**Ticket.** Closes #411.

**How it was checked.** Two tests in `server/test/server/import/memory_test.exs`, both written and run red first: a too-short memory among good ones (no raise, no fact banked, the rest imported), and a too-short memory over an existing fact (the fact keeps its text). `menard run test --in server` on that file: 5 tests, 0 failures. Full `server:test` run on the committed head; result posted to the thread.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
