Feature: intake understands epics.

An epic is a ticket of kind `"epic"` that holds other tickets through `parent` links (epic → child).
It is never work itself. Teach `Server.Intake.next/1` (the ticket intake starts next in a workspace)
these rules, test-first, and commit:

- an epic is never picked;
- a child's effective priority is the higher of its own and its epic's (an epic's low priority never
  lowers a child's);
- inside one epic only its lowest-`sort` backlog child may compete; once that one is done the next
  step competes;
- among equally urgent candidates, a child of an epic that is already `doing` goes before a newer
  loose ticket and before the child of an epic not yet started;
- loose tickets keep their order (newest first), and a step another ticket blocks (a `blocks` link)
  is skipped.

No new public function is needed: this changes what `Server.Intake.next/1` returns.


The project is the Elixir/Phoenix app under `server/` (`cd server && mix test <file>` runs a test file).
