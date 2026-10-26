Uqbar now actually routes the needs in its group (ticket #643).

- `operator_inbox` renders from `Needs.grouped/1`: each item carries `key`, `route`, `recommendation`, `why`; settled items are omitted.
- The Uqbar role gains THE INBOX LOOP: read the inbox, `settle_need` or `pass_up_need` each `route: uqbar` item; seats, quota and `tool_denied` are never its to route.
- New `Server.Office.NeedsPage`, run from `Server.Jobs.Drain` every minute: posts one `tlon` message on Uqbar's study naming newly unpaged keys (durable in `payload["need_page"]`, no migration). Debounced: skipped while Uqbar is mid-turn and within 5 min of the last page.
- Fail-open and `uqbar_route_minutes` are untouched.

Checked: new tests in `server_test.exs`, `profiles_test.exs`, `needs_page_test.exs` written red first; `menard run check` in server: 2137 tests, 0 failed. The live check (a fresh need is paged and gets a `need_routing` row within 30 min) runs after the release cut.
