A ticket arrives on the root thread: `@tertius intake — ticket #244: office: rewrite the room
renderer in a canvas library for speed`. It quotes no message, post or suggestion: no one asked for
it in their own words, and its body is the title alone.

The tech lead's read, posted on the lobby: "not on main, nothing in flight. I can't find who asked
for this or what problem it solves — the renderer isn't slow in any report. Sourceless: don't staff
it."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · office · free
- zunz · builder · senior · office · free
- yu · builder · greybeard · server · free (the tech lead)
- runeberg · planner · senior · — · free

Route it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
