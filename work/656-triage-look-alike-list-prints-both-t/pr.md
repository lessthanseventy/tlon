Triage look-alike list prints both tickets' titles (#656)

`Server.Triage.pairs/2` rendered each look-alike pair as `#A / #B: <A's title>`, so the
title read as belonging to the second id. Beatriz hit it on four triage runs.

Each side now prints its own title: `#A <title A> / #B <title B>`.

Scope is the print only. The pairs being unrelated is the matcher being too loose, which
is ticket #713 (follow-on, not touched here). `Server.Recurrence` is unchanged.

Checked: `menard run test --in server test/server/triage_test.exs` was red before the fix
(the look-alike line read `#11 / #12: The rack reads all …`) and is 4 tests, 0 failures
after. The `Look alike` assertion now requires each twin's title after its id.
