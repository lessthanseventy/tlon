Fire drill during a running scene is refused instead of stacking on it.

`play("drill")` never checked `this.running`, so a drill fired while a scene (duck, zoo, meteor, power cut) was on set its own alarm over the top of it. It now returns early, the same refusal `event()` gives a second scene. The `f` key is unchanged otherwise, and the drill still plays when nothing is running.

Closes #307 (follow-up from #255).

Checked:
- New test in `office/test/panic.test.ts` ("a drill during a running scene is refused, not stacked"): RED first, failing with `Expected: false, Received: true` on `alarmed`; GREEN after the one-line guard in `office/kit/sim.ts`.
- `bun test` in `office/`: 559 pass, 0 fail, 74 files.
- `tsc --noEmit` in `office/`: no errors.
