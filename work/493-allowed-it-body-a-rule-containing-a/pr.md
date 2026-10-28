# "Allowed it" body: a rule with a backtick stays one code span

Closes #493.

The "Allowed it" message wrapped the rule in single backticks, so a refused command holding a backtick (e.g. `echo \`date\``) nested them and broke the Markdown render. A backslash does not escape inside a code span, so both copies (`server/lib/server/alerts.ex`, `office/tui/data.ts`) now fence with one backtick more than the rule's longest run, spaced inside. A rule with no backtick renders exactly as before.

Checked: a test on each side (`needs_test.exs`, `needs-surfaces.test.ts`) went red, then green.
