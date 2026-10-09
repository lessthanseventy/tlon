Ticket (epics, step 1b): a ticket of `kind: "epic"` holds other tickets through `parent` links
(`Server.Tickets.link(epic_id, child_id, "parent")`: `from` is the epic, `to` the child). The link
exists already but nothing enforces the shape of the hierarchy. Make `Server.TicketLink.changeset/2`
(`lib/server/ticket_link.ex`) enforce, for `kind == "parent"` links only, returning an error changeset
(`Tickets.link/3` then returns `{:error, changeset}`), with these exact messages:

- `from` must be an epic: error on `:from_id`, `"only an epic can be a parent"`.
- `to` must not be an epic (no epic under an epic): error on `:to_id`, `"an epic cannot have a parent"`.
- a child has one parent: if `to` already has a `parent` link from a *different* epic, error on `:to_id`,
  `"already has a parent epic"`. Linking the same epic and child again stays `{:ok, _}` (idempotent).

Other link kinds (`blocks`, `relates`, `duplicates`) are unaffected, and a ticket id that does not exist
is left to the foreign-key constraint, not a new error. Add tests to `test/server/epics_test.exs`;
keep `mix test` green.
