# approve

Second round. Both blocking findings from the first review are fixed and verified on the branch;
the third (visibility log line) I'm dropping to a follow-up — the dangerous silent path it guarded
is now closed by the array gate, so what remains silent is a *legitimate* reclaim.

## finding 1 (was blocking, fixed) — recover only on a genuine array reply

The reclaim branch is now `if (superseded && Array.isArray(wakes))` (mod.ts drainWakes). Verified the
full path: `call` (mod.ts:95-98) returns the raw string when `JSON.parse` throws, so a non-JSON
`take_wakes` reply (mid-restart body, proxy 502, empty string) reaches `drainWakes` as a string. The
superseded-object check at line 211 misses it (`typeof string ≠ "object"`), and the reclaim guard
misses it (`Array.isArray(string) === false`). The session stays stopped — the safe default. The
seat-steal path (spurious `registerNow` → `supersede_live` ends the live newer session) is closed.

Normal recovery still works: `[]` and `["wake"]` are arrays, so reclaim fires and, for a non-empty
array, falls through to the wake-draining loop. The load-bearing comment explains the why.

## finding 3 (was blocking, fixed) — pin the non-array case

New test "a superseded session does not claim the seat back on a reply that is not a wake list":
`take_wakes` returns `{superseded: true, by: 9, text}` then the raw string `"upstream hiccup, not
json"`; asserts register count stays 1 and submitted stays `[text]`. The engine sentinel
(`typeof w === "string" ? w : JSON.stringify(w ?? [])`) passes string entries through verbatim
instead of JSON-stringifying, so `call` gets a real non-JSON reply. Traced both polls: first sets
`superseded` and submits the stop text; second hits neither guard and is a no-op. Correct.

## finding 2 (was blocking, now follow-up) — make reclaiming the seat visible

Dropping as a blocker. The detectability-4 concern was about the *silent seat-steal* — a stopped
pane wrongly taking the seat back with no sign. That path is gone (finding 1). The reclaim that
remains is the legitimate one: a real array reply means the server says the seat is free, and
re-registering is the intended action. A `note($, "take_wakes: no longer superseded — claiming the
seat again")` line next to the re-register is still worth having for debugging, but it no longer
guards against a dangerous silent action, so it does not block this fix.

## what stays

The "say so once" logic (`if (superseded) return;` inside the superseded-object block) and the
recovery test (two registers, missed wake submitted) are both correct and unchanged from the first
round's endorsement. The non-blocking note about a two-stale-pane register race converging to one
holder via `supersede_live` + Orphans still stands — not worth a ticket.