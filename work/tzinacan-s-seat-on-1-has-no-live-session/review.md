# request_changes

First verdict was approve; revised after the risk grade surfaced a real blast path I missed.
The core fix is correct and I keep endorsing it — a superseded session must keep polling and reclaim
the seat when the newer one is gone. `Tokens.resolve` attaching the *current* live session at read
time (nil when none) makes `take_wakes` answer non-superseded on recovery, so the design holds. Two
changes needed before this lands.

## 1 (blocking) — recover only on a genuine array reply

`call` (mod.ts:96-98) returns the raw `text` when `JSON.parse` fails — it does not throw. So any
non-JSON reply to `take_wakes` while superseded (a mid-restart body, a proxy 502 page, an empty
string) skips the `superseded`-object check and falls into the recovery branch, firing `registerNow`.
`register` on a back-up server calls `Staff.start_session` → `supersede_live`, which ends the **live
newer session** and routes wakes to the old pane. Silent seat-steal — the ticket's own failure mode,
inverted.

The server signals "the seat is free" only one way: `Server.Wake.take(...)` → an array (possibly
empty). Tighten the guard so nothing else recovers:

```diff
-    if (superseded) {
+    if (superseded && Array.isArray(wakes)) {
```

This keeps the normal recovery (`[]` or `["wake"]`) and excludes strings, null, and non-superseded
objects. A malformed reply leaves the session stopped, which is the safe default — a stopped pane
holding no seat is strictly better than a stopped pane wrongly stealing one.

## 2 (blocking) — make reclaiming the seat visible

The grader's detectability-4 is fair: taking the seat back is silent. Add a citizen-log line next to
the re-register so a wrong reclaim is findable:

```js
if (superseded && Array.isArray(wakes)) {
  superseded = false;
  void note($, "take_wakes: no longer superseded — claiming the seat again");
  const pane = await $.env.get("TMUX_PANE");
  registration = pane ? { pane_ref: pane } : {};
  void registerNow($);
}
```

I am NOT asking for a user-facing "you hold the seat again" message. The old pane was told "Stop.";
whether to resume is the operator's call, and a wake arriving is the real signal to go on. The log
line is enough for detectability.

## 3 (blocking) — pin the non-array case

Add a test where `take_wakes` returns a superseded object and then a plain string; assert register is
still called once and the session stays stopped. The engine today always `JSON.stringify`s
`world.wakes?.shift() ?? []` (mod.test.ts:101), so it needs a way to return raw non-JSON text for a
take_wakes entry — e.g. a sentinel that the harness passes through verbatim instead of stringifying.

## what stays

The modified "say so once" test (one register, one stop text across three superseded polls) and the
recovery test (two registers, missed wake submitted) are both correct and should stay. The
non-blocking observation about a two-stale-pane register race converging to one holder via
`supersede_live` + Orphans still stands — not worth a ticket.