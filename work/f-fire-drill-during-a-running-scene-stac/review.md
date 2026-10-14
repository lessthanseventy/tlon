APPROVE — office/kit/sim.ts play("drill") now returns early when `this.running`, mirroring event()'s one-scene-at-a-time guard.

Verified by reading the diff and Sim code (tests not re-run by me):
- One-line guard, minimal, matches #307; the comment states the why.
- Test seeds a running "duck" scene, fires a drill, asserts `alarmed` stays false and the scene is still running — covers the regression.

Non-blocking, pre-existing: play("event") refused by event() falls through to the stand-in emote/say path, so a refused `e` over a running scene still makes everyone "!" — same stacking class (filed as follow-up).