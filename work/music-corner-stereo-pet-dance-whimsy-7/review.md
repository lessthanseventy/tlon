Verdict: REQUEST CHANGES — blocking crash bug, otherwise solid.

## Blocking: pollPlayer() crashes the whole TUI when playerctl isn't installed

`office/tui/main.ts:414`:
```ts
const r = Bun.spawnSync(["playerctl", "metadata", "--format", "{{ title }}|{{ artist }}|{{ bpm }}"])
rm.setPlayer(r.exitCode === 0 ? parseNowPlaying(r.stdout.toString()) : null)
```

Verified directly: `Bun.spawnSync` with a binary not on `$PATH` *throws* ("Executable not found in
$PATH"), it does not return a result with a non-zero `exitCode`. The spec (§"playerctl: polling and
fallback") only covers `playerctl` exiting non-zero or erroring "No players found" — it never
considers `playerctl` being absent from the machine entirely, which is the likely case on most
boxes (unlike `tmux`, which this project already hard-depends on elsewhere).

`main.ts:1263` installs a global handler:
```ts
process.on("uncaughtException", (e) => { leave(); console.error(e); process.exit(1) })
```
`pollPlayer()` has no try/catch, so the uncaught throw from `setInterval(pollPlayer, 2000)`
(`main.ts:1293`) hits that handler and exits the process — the entire office TUI crashes ~2s after
launch, and again ~2s after every restart, on any machine without `playerctl`. This is a regression
in the TUI's availability, not just a cosmetic miss on the stereo.

Fix — treat a failed spawn the same as a failed run (fall back to idle):

```diff
 function pollPlayer() {
   const rm = room()
   if (!(rm instanceof WideRoom)) return
-  const r = Bun.spawnSync(["playerctl", "metadata", "--format", "{{ title }}|{{ artist }}|{{ bpm }}"])
-  rm.setPlayer(r.exitCode === 0 ? parseNowPlaying(r.stdout.toString()) : null)
+  try {
+    const r = Bun.spawnSync(["playerctl", "metadata", "--format", "{{ title }}|{{ artist }}|{{ bpm }}"])
+    rm.setPlayer(r.exitCode === 0 ? parseNowPlaying(r.stdout.toString()) : null)
+  } catch {
+    rm.setPlayer(null)
+  }
 }
```

@daneri ESCALATE apply: the diff above, to `office/tui/main.ts`.

## Everything else checked out

- `kit/stereo.ts` (`parseNowPlaying`, `marqueeWindow`): pure, well-tested, matches spec's fallback
  rules (blank title+artist → null; non-numeric/absent bpm → null).
- `dancing()` predicate and the flip/bob overlay in `drawCat`/`drawDog`: both keyed off the same
  `this.player?.bpm ?? null` and `sc.tick`, satisfying the corkboard note (one shared clock, not
  independent per-pet timers). Non-null assertions on `bpm!` inside the `dance` branches are safe —
  `dancing()` already guards `bpm !== null` before `dance` can be true.
  `WideRoom.stereo()` draw placement (`Math.min(L0 + 96, W - 46)`) correctly avoids the overflow at
  minimum room widths that build-stage caught.
- Golden pixel-hash refresh in the test commit matches the new draw code; diff against main is
  otherwise clean per the rebase history on-thread.
- Scope held: no new tile, no new pixel art, no server route, matching the spec's explicit scope line.

No other spec-compliance or security issues found.