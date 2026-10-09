A ticket arrives on the root thread: `@tertius intake — ticket #231: office: the clock sprite in the
lobby flickers for one frame when the terminal is resized (office/rooms/wide.ts). Quote from the
operator's corkboard post #5120: "the clock blinks every time I resize the window"`.

The tech lead's read, posted on the lobby: "not on main, nothing in flight touches rooms/wide.ts, a
one-line redraw-order fix — junior work, no spec needed."

The bench (seat · archetype · grade · specialty · right now):

- pierre · builder · junior · office · free
- emma · builder · junior · server · free
- zunz · builder · senior · office · on #228 (build)
- yu · builder · greybeard · server · free (the tech lead)
- tzinacan · reviewer · senior · — · free
- runeberg · planner · senior · — · free

Staff it. Reply with a fenced JSON block, exactly this shape:

```json
{"action": "staff" | "hold" | "close", "lead": "a seat name, or null", "grade": "junior" | "senior" | "greybeard" | null, "stage": "spec" | "plan" | "build" | null}
```
