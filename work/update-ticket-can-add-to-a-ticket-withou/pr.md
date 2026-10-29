`update_ticket` can add to a ticket without wiping it (#542).

`labels` and `body` only replace, so holding a ticket (`held` label, reason in the body) lost its filing.
Two new params: `add_labels` (union with the existing labels) and `append_body` (after the existing body,
blank-line separated). `labels`/`body` replace exactly as before; a close's evidence still lands last.

Checked: new test in `server/test/server/mcp/server_test.exs` (red before: labels stayed `["bug"]`; green
after), `menard run test --in server test/server/mcp/server_test.exs` 103 tests, 0 failures, and
`menard run check --in server`.
