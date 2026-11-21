A ticket arrives on the root thread: `@tertius intake — ticket #231: house: the clock sprite on the
wall flickers for one frame when the window is resized (house/room.gd). Quote from the
operator's corkboard post #5120: "the clock blinks every time I resize the window"`.

The tech lead's read, posted on the lobby: "not on main, nothing in flight touches house/room.gd, a
one-line redraw-order fix — junior work, no spec needed."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · house · free
- emma · builder · junior · server · free
- zunz · builder · senior · house · on #228 (build)
- yu · builder · greybeard · server · free (the tech lead)
- tzinacan · reviewer · senior · — · free
- runeberg · planner · senior · — · free

Staff it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
