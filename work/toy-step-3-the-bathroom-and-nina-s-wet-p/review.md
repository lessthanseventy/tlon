# Review — toy step 3: the bathroom and Nina's wet paws

**Verdict: request_changes** — one real bug, small fix.

## Blocking

**Argos walks through the bathroom wall to reach the trail.** `kit/pets.ts` stepDog's trail branch routes to the first print with `aisle: first.y`. The first print is always inside the bathroom (she leaves the rim wet, so it lands at ~(38,172)). `floorPlan.route` goes to the office lane (x=94) at HALL, then along y=172 to x=38 — straight through the bathroom's right wall (x 78–80, y 152–183) and past the tub. Every trail-follow does this; the pets test can't see it because its trail sits on the hall at y=188.

Fix: go in by the door, as she did, then to the first print:

```diff
--- a/office/kit/pets.ts
+++ b/office/kit/pets.ts
@@
+import { DOOR } from "./bathroom"
@@
-    const first = trail[0]!, to: Spot = { x: first.x, y: first.y, aisle: first.y, pose: "stand", face: "left", kind: "roam" }
-    d.path = [{ x: d.x, y: d.aisle }, ...ctx.route(d.x, d.aisle, to), ...trail.slice(1).map((p) => ({ x: p.x, y: p.y }))]
+    // in by the door, as she went: a route straight to the first print cuts through the bathroom's wall
+    const first = trail[0]!, door: Spot = { x: DOOR.x, y: DOOR.y - 3, aisle: DOOR.y + 5, pose: "stand", face: "up", kind: "roam" }
+    d.path = [{ x: d.x, y: d.aisle }, ...ctx.route(d.x, d.aisle, door), { x: first.x, y: first.y }, ...trail.slice(1).map((p) => ({ x: p.x, y: p.y }))]
```

Worth a test in the style of pastimes.test's "no wall is walked through": seed a trail starting at RIM_FLOOR, let him take it, and check his path's segments against `plan.blocks`.

## Verified

- Read the full diff (11 commits). Trip routing (`catDrink` mirrors `catDo`'s via/door pattern; `via` maps RIM→RIM_FLOOR so her next idle move comes down first), print laying/pruning, fade, door-open hold, the plant's aisle moved to HALL so it no longer routes through the room: all sound.
- `cd office && ../scripts/cap.sh bun test`: 422 pass. The 5 failures are refresh/terminal tmux tests failing on `Operation not permitted` / EROFS on /tmp — my sandbox has no unix sockets; not this branch. bathroom, bathroom-trip, pets, pastimes and golden all green.

## Non-blocking (filed as follow-ups)

- The four `refresh.test` hardening commits ride along on a bathroom branch; fine, but they'd be easier to bisect as their own PR.
