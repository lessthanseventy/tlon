APPROVE.

Right then: the change does what it says. In `Staffing.windowed?/4`, an untagged leaf (`tab.agent` nil) now vouches only for `Channel.thread_lead(thread_id)`, where before it vouched for every agent's session on the thread. A tagged leaf is unchanged. `thread_lead` returns nil for an unassigned thread, and nil never equals a session name, so an untagged leaf on a leadless thread vouches for nobody. That is the safe direction.

The new test is parameterised over tagged and untagged leaves. Both cases restaff the thread to borges and assert that hronir's old session ends and borges's survives.

I read the diff and `Channel.thread_lead` only. I did not run the suite, so green is unverified on my side. The landing gate runs the full suite.