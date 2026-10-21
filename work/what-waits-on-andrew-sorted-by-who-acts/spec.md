# Spec: what waits on Andrew, sorted by who acts (#167)

## Rule
An item reaches the operator's queue only if it has an answer he must give. Information goes to the answering machine. What the crew owns goes to the sheriff's clipboard.

## Surfaces
- **phone**: an answer is owed. The only count in the top bar ("N waiting on you"); it rings while N > 0.
- **machine**: information addressed to the operator. Light blinks, "N new messages". Heard when opened; leaves once heard or after a day.
- **clipboard**: the crew owns it. Replaces the red issues sign by the door. Each row shows its owner and the ticket or workline tracking it.

`Server.Office.Needs` stays ONE derived list. Each item gains `surface` ("phone" | "machine" | "clipboard"). `level` stays (blocking/decide order within a surface). The surface is a pure function of `kind`: `Needs.surface/1`.

## Table (every kind on origin/main)
| kind | surface | why |
|---|---|---|
| gate, question, dialog, ask | phone | approve / reply / pick |
| seats | phone | raise the cap |
| quota | phone | pick another crew |
| no_seat | phone | hire or hand off |
| tool_denied | phone | allow the rule |
| mention | machine | information |
| rollout | machine | information |
| issue | clipboard | crew owns; ticket/workline tracks |
| stalled | clipboard | crew owns |
| verify_failed | clipboard | back to build, sheriff copy |
| pr_blocked | clipboard | crew rebases/relands |
| publish_failed | clipboard | crew republishes |
| release_failed | clipboard | PM retries |
| job_failed | clipboard | crew owns |
| stranded | clipboard | crew owns |

(Provisional: pr_blocked, publish_failed, release_failed await the operator's answer, ask #11491.)

## No unrouted kind
`Needs.kinds/0` lists every kind; `surface/1` has no catch-all clause (FunctionClauseError). Tests: (1) every kind in `kinds/0` has a surface; (2) every item `list/0` produces from fixtures of each emitter carries a `surface` in the set. A new Need kind cannot compile into use without a `surface/1` clause, and the test fails until it is added to `kinds/0` and the table above. While this is in flight, a new kind rebases onto it and adds its row; it defaults to nothing.

## Office payload (all three surfaces agree)
`/api/office` `needs`: `{phone: [item], machine: [item], clipboard: [item], counts: {phone, machine, clipboard}}`. Item: existing fields plus `surface`, and for clipboard `owner` (lead/handle) and `tracking` (ticket id or workline slug). The top bar reads `counts.phone` only. Machine: item removed once heard (opened) or older than 24h; needs a `heard` record (like `need_dismissal`, keyed by item key).

## Done when
- Tests put each kind on its surface; 2026-10-10 state (issues 13-16, mentions #191 and #207) gives phone 0, machine 2, clipboard 4.
- Render/golden test: ringing phone (N>0) and the machine's blinking light.
- Moduledoc and TUI inbox (`i`) updated in the same change (inbox groups by surface).

## Collisions
- `Server.Office.Needs` is hot (a2dec49, d46323b): land as one small PR; rebase before opening.
- #557 (LANDING & CHECKS list in the rack) also touches the top bar and rack: land whichever is first; the other rebases. Not combined.

## Open
- Consumer file paths (top bar, rack sign, TUI inbox) not yet verified: author had no working shell.
