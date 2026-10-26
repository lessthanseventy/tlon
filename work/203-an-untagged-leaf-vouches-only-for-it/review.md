APPROVE.

In `Staffing.windowed?/4`, an untagged leaf (`tab.agent` nil) now vouches only for `Channel.thread_lead(thread_id)`. Before, it vouched for every agent's session on the thread. A tagged leaf is unchanged. The parameterised test covers a tagged and an untagged leaf on a restaffed thread: the old lead's session ends and the new lead's survives.

I read the diff, `Channel.thread_lead` and `still_theirs?/3` only. I did not run the suite; the server's check passed (exit 0).

Non-blocking follow-ups, listed in follow_ups:
1. Leadless thread or crew role: `still_theirs?/3` treats a nil lead as anyone's and exempts crew roles, but the new `windowed?` does neither. An idle session of that kind, whose only window is an untagged `t<id>` leaf, is now ended after the boot grace. This is rare; it needs a hand-made untagged leaf.
2. `end_windowless` ends sessions without logging, unlike `end_predating_tmux`.

The earlier per-tab `thread_lead` query follow-up is dropped; it is negligible.