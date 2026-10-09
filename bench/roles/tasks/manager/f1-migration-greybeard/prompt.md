A ticket arrives on the root thread: `@tertius intake — ticket #236: db: the event table's `kind`
CHECK must admit `superseded` and `forgotten`, and the merge queue's gate must run the doctor's
integrity check before it lands anything. Quote from the operator's lobby post #5240: "the librarian's
events are refused by the db, and I want the gate to catch a broken store before a landing"`.

The tech lead's read, posted on the lobby: "not on main, nothing in flight touches the migrations or
the merge gate; a migration on a live table plus a gate change — greybeard work. Needs no spec, the
ticket is the spec; start it at build."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · office · free
- emma · builder · junior · server · free
- zunz · builder · senior · server · free
- yu · builder · greybeard · server · free (the tech lead)
- tzinacan · reviewer · senior · — · free
- runeberg · planner · senior · — · free

Staff it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
