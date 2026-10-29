Approve. Note: no free reviewer is at the builder's grade (greybeard); reviewed by tzinacan below it.

Scope: trust.ex, workline.ex (hand_to + auto_land_note), trust/workline tests.

Checked:
- leads_line/3 + model_of/1: bare line unchanged, so existing `like` matches work and old lines read as model nil.
- record/2 uses strpos (not LIKE; `_` in labels is not a wildcard). record/1 counts all models, unknown included.
- builder/1 returns {name, model}; only allowance/2 calls it. allowance stays per coworker (operator #16512), evidence gains model; the note reads "earned by X on M".
- hand_to/4 passes Profiles.model_label; nil posts the bare line.
- `menard run test --in server test/server/trust_test.exs`: ok, 4 tests. I did not run workline_test or the full gate; pr.md's claims there are unverified by me.

Non-blocking: strpos matches anywhere in the body, so a note containing the literal "[model: X]" would miscount (low risk, system-written). Same-lead model change keeps the old attribution (spec decision 2).