APPROVE

Right then: the spots read plain. `tool_denied_need` gains `shape=` (`plain` default, `backtick`). Any other value raises before the thread opens, so a bad value seeds nothing. The default path is unchanged (`echo hi`).

Verified: `menard run test --in server test/server/smoke/fixtures_test.exs` gave ok, 18 tests, 0 failures. That includes the new backtick case and the unknown-shape case, which asserts `Needs.list()` stays empty. The diff matches the ask. The AGENTS.md note sits beside the spec grammar, and the pr.md says plainly that no live `release:smoke` was run.

Not verified: driving the shape in a real smoke. That belongs to QA.

No blocking findings.