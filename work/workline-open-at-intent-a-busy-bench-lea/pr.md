Workline.open at intent: a busy bench lead is passed over for a free one.

Closes #721.

At intent, `restaff/1` took the bench's lead (first builder, else first seat) with no check that
the seat was free. A busy lead named as `lead:` therefore read "→ X leads (intent stage)" and then
"→ X leads, not X: X is leading another workline", breaking one coworker, one workline. The intent
clause now filters the bench with `leading_another?/2` first, the same rule every other stage's
restaff already applies. If nobody is free, the thread stays unchanged.

Checked: two new workline_test cases went red first (left "tertius", right "hronir") and are green
with the change; `mix format --check-formatted` and `mix compile --warnings-as-errors` pass; the
workline_test file runs 96/96.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
