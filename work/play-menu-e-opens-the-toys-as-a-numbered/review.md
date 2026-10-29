# Review: play menu — E opens the toys as a numbered card (#607)

**Verdict: request_changes.** Branch `work/play-menu-e-opens-the-toys-as-a-numbered` at 30b144d, read against origin/main. Three findings; the first blocks.

## 1. A toy fired from a card loses the card, and the person under it (blocks)

`toyKey` (office/tui/main.ts) opens `{ kind: "play" }` with no `from`. `open()` adds `from` only for person/thread/look/review/issue, so the play card's row `run` (`back(); playDo(b.id); …`) lands on home every time. `playDo` reads `mode` after that `back()`, so `under = mode.kind === "person" ? mode.name : null` is always null, and the `mode.kind === "pet" && mode.who === "dog"` branch of `play.pet` is dead.

Consequence, versus main: on a person card, `P` patted that person and `C` called someone over to them. Now `E 8` pats the cat, `E 9` calls someone to `bench[1]`, and Esc after a toy no longer returns to the card you were on. The spec kept every toy "two keystrokes away"; it did not retarget them.

Fix (two lines):
```
-  | { kind: "pet"; who: "cat" | "dog" } | { kind: "play" } | …
+  | { kind: "pet"; who: "cat" | "dog" } | { kind: "play"; from?: Mode } | …

-    case "E": open({ kind: "play" }); draw(); return true
+    case "E": open({ kind: "play", from: mode.kind === "home" || mode.kind === "play" ? undefined : mode }); return true
```
(`open()` already draws.) Test that goes red first: in navigation.test, `tab` onto a person, `E` `8`, wait for "pat pat", expect the person card still on screen.

## 2. office/AGENTS.md still names the retired keys (fix in the same round)

Line 21: "`F` (`play("drill")`) raises a `DRILL`-long one" and "`e` in the sandbox plays one". F is unbound by this branch; `e` was never the key. Say "the play card's fire drill row" and "row 1 of the sandbox's play card". Same-commit doc law.

## 3. The toyKey/playDo coverage test is now vacuous (follow-up)

sandbox.test "the help line's play keys are the keys toyKey() handles" now only proves `case "E"` exists. Nothing checks each `card:play` row has a `case "play.x"` in `playDo`; a row added to keys.ts with no case would be a card row that does nothing. Assert `case "${b.id}"` for every `PLAY_ROWS` entry over the `playDo` body.

## Not findings

- bench_contrast: "unmeasurable" (office/AGENTS.md is read by a seat, never loaded by the bench). Not a REGRESSION row.
- `mise run check` green on the branch is the server's verify run. I did not run the drive walk myself; "2 → Gary's at the dumpster in the wide room" is the builder's report, not verified here.
- Key table: sandbox-play is `["E"]`, card:play rows 1..9, digits exempt from the one-verb rule by keys.test's `guarded`. Matches the plan.