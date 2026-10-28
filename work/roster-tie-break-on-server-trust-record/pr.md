# Roster tie-break on Server.Trust record (#504)

`Server.Roster.pick/2` candidates may carry `trust` (`Server.Trust.record/1`). It is the last term in the sort before bench order: between seats equal on grade, specialty and builder's-model, the better first-time-landing rate wins. No record, or no finished build, is neutral (0.5), not worst. `Workline.restaff` and `suggest_lead` pass the record in, so Roster stays pure. Closes #504.

Checked: new `roster_test.exs` cases (better record wins; never overrides grade, specialty or model; nil/zero neutral; ties keep bench order) red before, green after.
