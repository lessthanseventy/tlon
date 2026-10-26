# Review — hall `e` (d1c7c76, branch work/hall-spec-2-e-edit-look-soul-from-the-ha)

**Verdict: request_changes.** The code is clean and tested, but the look half of `e` is not what spec §2 names.

Read: the whole diff (8 files, +127/-14), `work/toy-step-9-the-hiring-hall-swipe-on-gene/spec.md` §2, §4, §7, §8, `office/kit/hall.ts`, `office/kit/parts.ts` (`nextPart`), `office/tui/main.ts` (`ask`, `hallHire`, the `look` card). No spec or plan exists on this workline; the spec of record is toy-step-9's, as scharlach said at #14182. CHECKS: `mise run check` exit 0 (office 911 pass); `bench_contrast` unmeasurable, not a REGRESSION row, so not a finding.

## Findings

1. **Spec §2 names the existing look editor; the build cycles one slot in place.** The spec's witness: `e | edit the look (existing look card/editor) or the soul text`, and §7: "the look editor reuse are the seam". The diff instead does `cyclePartRow(hall, ctx, what)` on a slot row and nothing else for the look. A `Look` is `hair, hairRole, decor, fav, skinRole, outfit, accessory, body, parts, custom` (`kit/sprites.ts:15`); from the hall only the six `parts` slots are reachable, with no dials (`nextPart` returns `{ id }`). Hair, skin, outfit, body and the custom pixels cannot be edited, which is most of "edit the look". The fix the spec asks for: `e` on a slot row (or anywhere on the look) opens the `look` card over a draft of `c.look`, whose save writes the draft back into `hall.overrides` (parts and the other Look fields) instead of `looks.json`, since the candidate has no name in `looks.json` until hire. That needs a small seam in the `look` card (a draft source and a save target), which is the §7 reuse. If the tech lead would rather amend the spec to per-row cycling, say so on the thread and this finding drops; I have asked him.

2. **Scope beyond the ask.** Ticket #298 is "spec §2 `e` (edit look/soul)". The diff also adds name, pitch, archetype, grade and specialty edits (`editField` on five fields) and a `soul` row. None is in §2. The field edits are sound (name gated by `SOUL_NAME` and `taken`, vocab checked against the roster, blank refused) and I found no fault in them. Whether they stay is the lead's call; not blocking by itself. The `soul` row is needed for the soul edit and stays.

3. **`cyclePartRow` stores `{ id }` only.** A rolled part can carry dials; once the cycle comes round to the rolled id, the override is `{ id }` without them, so the card never shows the rolled look again. Minor; goes away if finding 1 moves the edit into the look card, which has `nextDial`.

4. **Not driven.** pr.md says "Not driven through `office:drive`". The hall's plan tasks (toy-step-9 plan, task 5 Done line) make an `office:drive` run part of done for hall work. I did not drive it either. The resubmission owes one run: `h`, tab to a slot row, `e`, then tab to the soul row, `e`, write, enter, and the card showing the edit.

## Verified, no finding
- Security: an edited name passes `SOUL_NAME` before it can become `souls/<name>.md`; `cleanOverrides` re-checks it on load; the soul file is written `wx`, never over an existing one. Pitch and soul are free text that only reach the sandbox dir or `souls/` on hire.
- `pass` drops an unlocked edit and keeps a locked field; `maybe` carries the edits onto the pile; `bringBack` restores them. The tests cover these.
- `HALL_ROWS` grew by one and `stepRow` wraps on it; no slot name collides with a field name, so the `SLOTS.includes(what)` branch in `hallEdit` is unambiguous.
- `hall.e` is scoped `card:hall`; the other `e` bindings are each on their own card scope.
