smoke: tool_denied_need:shape=backtick, a refused command holding a backtick (#702)

QA of #493 could not drive the allow-rule fence end to end: `tool_denied_need` always seeds `echo hi`, so
no smoke ever showed a rule with a backtick in it. A spec travels as one word through
`TLON_SMOKE_FIXTURES` and the shell, so the command cannot be a param value. Following the `health_need
what=` pattern, `shape=` names it instead: `plain` (`echo hi`, the default, unchanged) or `backtick`
(``echo `date` ``). Any other value raises. The catalog defaults gain `"shape" => "plain"`, and the
seeder's `command` and `summary` take it.

`server/AGENTS.md` notes the named-shape form beside the spec grammar.

Closes #702.

Checked: `menard run test --in server test/server/smoke/fixtures_test.exs` is green, 18 tests, 0 failures.
The new cases were red first: `shape=backtick` raised `unknown param shape`, and the bad-value case now
asserts the `shape= is plain or backtick` message. Not run: a `release:smoke` or a `tool_denied_need:shape=backtick`
smoke on the card. That needs the QA seat's scratch release.
