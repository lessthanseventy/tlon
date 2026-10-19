# Glossary — one meaning per noun

Every row is one word with one meaning. A word that needs two meanings is two words, and the second
one is a pending rename below. `scripts/check-names.sh` (`mise run check:names`) holds this file: every
`Server.*` module, `mise run` task and `scripts/*` file named in the **lives in** column must exist,
and the retired words under **never say** must not appear in any `AGENTS.md`, in `office/tui/*.ts`
user-facing strings, or in `docs/plans/` files dated 2026-10-19 or later. A **lives in** cell that
begins `pending:` records a rename not yet made; the gate skips it. The source of the decisions is
`docs/plans/2026-10-13-cohesion-off-the-happy-path.md`, Cause 2.

| term | meaning | lives in (module/field/task) | never say |
|---|---|---|---|
| lead | A thread's lead: the one coworker a thread is assigned to (`Server.Staff.assign/2`; none shows as unled in triage). | `Server.Staff`, thread field `agent_id` | "manager" for it; "tech lead" |
| designated lead | A workspace's manager: the coworker the standing thread defaults to. Not a thread's lead. | `Server.Channel` (`designated_lead/1`) | "lead" bare |
| tech lead | The bench's first `builder` (else its first seat): the default worker to address. | `Server.Coworker` (`lead/1`) | "lead" bare |
| bench | Everyone seated in a workspace: the employed seats. Not the live sessions (that is the roster). | `Server.Coworker` | "crew", "team" |
| roster | The in-flight list of live sessions: who is on the clock. | `Server.Staff` (`roster/0`) | "bench" |
| crew | A named shift only (day, night, ...): a set of coworkers a taken offer swaps in. | `Server.Shifts` (`crews/1`) | "crew" for the whole cast or for the tmux backend; "team" |
| crew backend | The seam that opens a terminal for a coworker. Pending rename: `Server.Crew` becomes `Server.Spawn`, so "crew" stops meaning two things. | pending: `Server.Crew` → `Server.Spawn` | "crew" |
| staffing | Assigning a thread to a coworker. | `Server.Staff` (`assign/2`) | "the sweep" |
| the sweep | The per-minute tmux pass that closes windows nobody needs. Pending rename: the module and job are named `Staffing`, which collides with staffing a thread. | pending: `Server.Staffing` → `Server.Sweep` | "staffing" |
| triage | The server's one meaning: what needs a hand in a workspace, namely blockers, failed checks and unled threads. | `Server.Office.Room` (`triage/1`) | "what awaits the operator" (that is Needs) |
| gate | A workline stage parked on the operator; a Need of kind `gate`. | `Server.Workline`, `Server.Office.Needs` | "gate" for `mise run check`, for hard limits, or for the release gate |
| the check | `mise run check`: the green-before-commit gate. | `mise run check` | "the gate" |
| the release gate | The PM's gate on cutting a release. Pending: it becomes a Need of kind `gate` with `scope: release` (today kind `dialog`). | `Server.Release.PM`, `Server.Release.Candidate` | "gate" bare |
| Need | One item in what waits on the operator: the header, the inbox and the home card all read the same list. | `Server.Office.Needs` | "task", "todo", "alert" (an alert is the desktop's, `Server.Alerts`) |
| schedules | Oban cron or one-shot work the operator set: an agent prompt, a workline or a script. The TUI's `a`. | `Server.Schedules`, `Server.Schedule` | "calendar" |
| calendar | The operator's `.ics` meetings, read for alerts. | `Server.Calendar` | "schedules" |
| the room | The office screen: the pixel-art floor behind every card. `ctrl+] room` returns to it. | `office/tui/main.ts` | "lobby", "console", "cockpit" for the screen |
| the front desk | A workspace's standing thread, where the operator talks to the bench. Its stored title is still `lobby` (pending). | `Server.Bootstrap` (`ensure_standing/1`) | "lobby" |
| at their desk | A coworker's home window: the tmux window that is theirs. | `Server.Arbiter` | "lounge" for a live window |
| the office | The operator's surface: the standalone TUI over the server. | `office/tui`, `mise run office:check` | "console", "cockpit" |
| funes | The Erlang node name of the server (`funes@`) and nothing else. The product is Tlön. | `server/rel/env.sh.eex` (`RELEASE_NODE`) | "funes" as a product name |
