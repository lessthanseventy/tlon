APPROVE

Reviewed main...dc6bf02 (office only; no server code touched).

Spec compliance: the poster hangs between stereo and clock (`WideRoom.poster`), its line comes from `posterOf(now)` over a fixed 7-line list keyed by local date (stable all day, flips at local midnight), tip on hover, palette roles only, skipped when the wall lacks room (x0+w > width-34). Matches the spec.

Checks: the new `act.kind "poster"` is not switched on anywhere (grep: Act kinds are only constructed in wide.ts), so there is no exhaustiveness fallout. Tests cover day-stability and change, one hit at width 900 with today's line in the tip, and none at 540. The 900 golden is updated, as expected for a new draw. The server's verify recorded `mise run check` exit 0.

Nits (non-blocking): the office/AGENTS.md line is now long; the `Act` variant only tags the hit (same as stereo).

Unverified by me: I did not render the room or run the suite myself. I'm relying on the recorded check and the diff.