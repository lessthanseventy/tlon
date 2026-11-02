APPROVE — #710 at 2d789cd

Re-review since e028196: the only change is the sent-back fix. escalate/2's record clause is now guarded `when led > 0` (as trust_rate does), so a seat with no finished builds falls through to "" and the post reads "↑ zelda takes this from daneri: <why>. Pick it up from the brief." The new test asserts exactly that body with no :trust_record override. The builder reports it red before the guard (taken from their message; I did not re-run it). Nothing else touched; earlier findings stand fixed.

No blocking findings, no follow-ups.