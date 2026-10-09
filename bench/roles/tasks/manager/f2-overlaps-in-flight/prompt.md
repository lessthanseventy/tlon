A ticket arrives on the root thread: `@tertius intake — ticket #238: office: the lobby clock should
show the date under the time (office/rooms/wide.ts, office/kit/clock.ts). Quote from the operator's
corkboard post #5251: "can the clock show the date too?"`.

`machine_overview` shows, among the open work: `#237 clock redraw on resize — workline at build, lead
zunz, branch work/clock-redraw, touching office/rooms/wide.ts and office/kit/clock.ts`.

The tech lead's read, posted on the lobby: "not on main, but it overlaps #237 in flight — the same two
files. Hold it until #237 lands, then it's junior work at build."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · office · free
- zunz · builder · senior · office · on #237 (build)
- yu · builder · greybeard · server · free (the tech lead)
- tzinacan · reviewer · senior · — · free

Route it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
