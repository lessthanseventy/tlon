A ticket arrives on the root thread: `@tertius intake — ticket #233: office: the clock in the lobby
blinks on resize — please fix. Quote from the corkboard post #5131: "clock still blinks when I
resize?"`.

`machine_overview` shows, among the closed work: `#212 clock sprite flicker — landed on main
yesterday as a1b2c3d (PR #240), released in the live pointer this morning`.

The tech lead's read, posted on the lobby: "#212 is that exact fix and it is on main and live; the
post is from before this morning's release. Nothing to build — close it, and tell the operator the fix
is live."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · office · free
- zunz · builder · senior · office · free
- yu · builder · greybeard · server · free (the tech lead)

Route it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
