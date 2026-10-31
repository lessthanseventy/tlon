Reviewer grade: NOT senior. No free reviewer is at the builder's grade (senior); this review is by ulrikke on the cheap profile, read-only, tests not run by me.

Verdict: approve.

Checked by reading the diff vs main:
- Server.Workline.Continuation: gap_wait returns {:later, at} inside the gap and requeue sits before the budget check, so the requeue cannot spin.
- Requeue uniqueness keys [:thread_id, :quiet] over states [:available, :scheduled] lets a running check requeue itself (executing rows excluded), as the new test asserts.
- Jobs.Continue passes quiet from args ahead of :continue_opts; keyword order keeps the job's own quiet flag.

Follow-ups (non-blocking):
- Jobs.Continue reads a test seam (:continue_opts) from app env in production code. Move it behind a test-only hook.
- lead_last_post_at now computes max over all lead messages instead of a bounded exists-within-window query. Fine at current volume; index check if threads grow.