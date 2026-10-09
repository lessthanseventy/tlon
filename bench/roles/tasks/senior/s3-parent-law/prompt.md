Feature: the parent law for tickets.

Tickets have a `kind` (`"ticket"` or `"epic"`) and links (`Server.Tickets.link/3`, kind
`"parent"` runs from an epic to its child; `Server.Tickets.links_of/1` reads them both ways). The
`parent` link has no rules yet. Give it these, test-first, and commit:

- only an epic can be a parent: linking from a non-epic ticket fails with the changeset error
  `{"only an epic can be a parent", _}` on `:from_id`;
- an epic cannot have a parent: linking to an epic fails with `"an epic cannot have a parent"` on `:to_id`;
- a ticket has at most one parent: a second epic adopting it fails with `"already has a parent epic"`
  on `:to_id`; adopting again into the *same* epic stays fine (idempotent `{:ok, _}`);
- an epic adopts a ticket and both ends read it back through `links_of/1` (direction `:out` from the
  epic, `:in` from the child).

Other link kinds are unchanged. `Tickets.link/3` returns `{:error, changeset}` for a refusal, so the
rules belong in `Server.TicketLink`'s changeset.


The project is the Elixir/Phoenix app under `server/` (`cd server && mix test <file>` runs a test file).
