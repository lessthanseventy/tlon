A ticket arrives on the root thread: `@tertius intake — ticket #241: server: the PM should post a
weekly digest of what shipped, built from the release events. Quote from the operator's lobby post
#5266: "I'd like a weekly what-shipped note from the PM"`.

The tech lead's read, posted on the lobby: "not on main, nothing in flight overlaps. It spans the PM,
the schedules and the release events, so it wants a plan before anyone builds — start it at plan.
Senior work once planned."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · office · free
- zunz · builder · senior · server · free
- yu · builder · greybeard · server · free (the tech lead)
- tzinacan · reviewer · senior · — · free
- runeberg · planner · senior · — · free

Staff it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
