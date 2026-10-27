# #679 plan — session-stamped authorship

Spec: `spec.md`. All paths under `server/`. Run tests with `menard run test <file>`; final gate `mise run check`.
Each task = one commit, test first (red → green). Ending each commit message with the Co-Authored-By trailer of the model that wrote it.

**Shared convention (decide once, keep DRY):** the session id is an explicit **opt**, `session_id: id | nil`, never an
attrs key and never in any `cast/3` list. Setters: `Channel.post(attrs, opts \\ [])`,
`Dossier.record_event(attrs, opts \\ [])`, `Dossier.record_check(attrs, opts \\ [])`, `Tickets.file(attrs, opts \\ [])`.
Callers that are not an MCP tool pass nothing → NULL (system authors keep NULL for free).

## T1 — migration + schema fields
- New `priv/repo/migrations/20261027120000_session_stamped_authorship.exs`:
  ```elixir
  defmodule Server.Repo.Migrations.SessionStampedAuthorship do
    @moduledoc false
    use Ecto.Migration

    def change do
      for t <- [:message, :ticket, :event] do
        alter table(t), do: add(:session_id, references(:session, on_delete: :nothing), null: true)
      end
    end
  end
  ```
- Add `belongs_to :session, Server.Session` to the schemas in `lib/server/message.ex` (after `belongs_to :thread`), `lib/server/ticket.ex`, `lib/server/event.ex`. Do NOT add it to any cast list.
- Test `test/server/session_stamp_schema_test.exs`: for each of Message/Ticket/Event, `Server.Repo.__adapter__` is unneeded — assert `:session_id in Schema.__schema__(:fields)` and that `Message.post_changeset(%{thread_id: 1, author: "a", body: "b", session_id: 9}).changes` has no `:session_id` (smuggling refused). Red first (field absent), then migrate (`mise run server:setup` / test db migrates on `TestDB`).
- Done: that test green; `menard run test test/server/session_stamp_schema_test.exs`.

## T2 — `Server.Authorship.label/2`
- New `lib/server/authorship.ex`: `label(author, session_id)`:
  - `nil` → `"#{author} · session unknown"`
  - id → loads `Repo.get(Server.Session, id)` (ended sessions still load); `"#{author} · pane t#{thread_id} #{pane_ref} · session #{id}"`; a nil `pane_ref` drops the pane segment (`"nolan · session 954"`); a row that vanished → unknown.
  - Include the moduledoc line: "the one place the format lives".
- Test `test/server/authorship_test.exs` (async: false, `TestDB.clean!`): create thread + agent + `Staff` session with `pane_ref: "%9"` (see `test/server/mcp/tokens_test.exs` for the fixture style); assert exact string `"nolan · pane t<tid> %9 · session <sid>"`, nil case, no-pane case.
- Done: green. Check `Server` boundary exports (`mise run server:check`) — add `Server.Authorship` to the boundary's exports if the compiler complains.

## T3 — stamp `Channel.post`
- `lib/server/message.ex`: `post_changeset(attrs, session_id \\ nil)` → after the existing pipeline `|> put_change(:session_id, session_id)`.
- `lib/server/channel.ex:74`: `def post(attrs, opts \\ [])`; pass `Keyword.get(opts, :session_id)`.
- Test (add to `test/server/channel_test.exs`, or new `test/server/channel_session_test.exs`): `Channel.post(%{thread_id:, author: "nolan", body: "x", session_id: 99}, session_id: s.id)` → row's `session_id == s.id` (attrs-key `99` ignored); `Channel.post(%{... author: "tlon"})` → NULL.
- Done: green.

## T4 — stamp events / checks
- `lib/server/event.ex`: `record_changeset(attrs, session_id \\ nil)` + `put_change(:session_id, session_id)`.
- `lib/server/dossier.ex`: `record_event(attrs, opts \\ [])` (line 122) passes `opts[:session_id]`; `record_check(attrs, opts \\ [])` (line 357) forwards `opts` to `record_event`.
- Test (`test/server/dossier_test.exs`): `record_check(%{thread_id:, cmd: "c", exit: 0}, session_id: s.id)` → `event.session_id == s.id`; without opts → NULL.
- Done: green.

## T5 — stamp tickets
- `lib/server/ticket.ex`: `file_changeset(attrs, session_id \\ nil)` + `put_change`.
- `lib/server/tickets.ex:24`: `file(attrs, opts \\ [])` → `Ticket.file_changeset(Keyword.get(opts, :session_id))` in the pipe (note the pipe currently goes `attrs |> Map.put_new_lazy |> Ticket.file_changeset()`; pass the arg).
- Test (`test/server/tickets_test.exs`): stamped vs NULL; attrs `%{session_id: 99}` ignored.
- Done: green.

## T6 — wire the MCP tools to the connection identity
Each tool already has `identity = Identity.from_frame(frame)`; pass `session_id: identity.session_id`.
- `lib/server/mcp/tools/thread.ex:77` `post_message`: `Channel.post(%{...}, session_id: identity.session_id)`; also `:440` (finish's summary post).
- `lib/server/mcp/tools/thread.ex:~560` `record_check`: `Dossier.record_check(opts…)` → `|> Dossier.record_check(session_id: identity.session_id)`.
- `lib/server/mcp/tools/workspace.ex:210` `file_ticket`: `Tickets.file(Map.put(...), session_id: identity.session_id)`.
- `lib/server/mcp/tools/workline.ex:~166` `verdict/4`: add `session_id: identity.session_id` to the `Workline.qa_verdict/5` opts (the `verdict` helper gets `frame`; call `Identity.from_frame(frame, touch: false)` there or thread the id in from `execute/2`).
- `lib/server/workline.ex:844` `qa_verdict`: `Dossier.record_check(%{...}, session_id: opts[:session_id])`. The `cmd: "qa by #{author}"` string stays byte-identical (`Diary.verdict/1` parses it).
- **Acceptance test 1 + 2** in new `test/server/mcp/authorship_test.exs`, driven like `test/server/mcp/server_test.exs` (real tokens/sessions; see its `call/5`): one agent (`nolan`) registered with two live sessions on two different threads (thread A / thread B, each its own token + `register`). Each calls `post_message`, `record_check`, `file_ticket`. Assert the three rows from A carry session A's id and B's carry B's, and that A≠B. Also `Channel.post(%{... author: "tlon"})` row is NULL.
- Done: green; this is the #8669 scenario.

## T7 — render
- `lib/server/mcp/brief.ex`:
  - `message/1` (line 180): add `"by" => Server.Authorship.label(m.author, m.session_id)` — surfaces in `get_message` (it calls `Brief.message/1`) and everything else rendering messages.
  - `ticket/1` (line 211): add `"filed_by" => Server.Authorship.session_label(t.session_id)` (tickets carry no author name, hence the 1-arity sibling added in T2: the same string without the author prefix; nil → `"session unknown"`; add its test case to T2's file).
  - `check/1` (line 168): add `"by"` using the event's `session_id` and the seat parsed from `cmd` when it starts with `"qa by "`, else just `session_label/1`. Needs `session_id` in the pattern match (`%Event{... session_id: sid}`).
- `lib/server/workline.ex:~858` QA brief: `post_brief(thread, "✓ QA passed (#{Server.Authorship.label(author, opts[:session_id])}):\n\n#{report}")`; the fail-path `bounce` text (`"QA (#{author}) drove it…"`) likewise.
- **Acceptance test 3** in `test/server/workline_qa_test.exs` (style: its `verdict` cases): `qa_verdict(thread, "pass", "nolan", report, session_id: s.id, artifacts: AllPresent)` → the `qa by` check event's `Brief.check/1` `"by"` equals `"nolan · pane t<tid> %9 · session <sid>"`, and the posted QA brief message contains that same string. Plus a `get_message`/`Brief.message` unit case: stamped row shows the label; pre-migration (NULL) row shows `"<author> · session unknown"`.
- Done: green.

## T8 — gate
- `mise run check` green (compiles with warnings-as-errors; boundary exports; names/task manual).
- Update docs only if a doc lists tool output fields (`rg -n '"reply_to"' docs ../AGENTS.md`); otherwise none.
- PR note: **includes a migration → landing gate is the operator's (#4242)**; recommend approve (additive, nullable, drop three columns to revert). No backfill.

## Order / sizing
T1 → T2 → (T3, T4, T5 independent) → T6 → T7 → T8. Each ≤ ~4 files. If T6 feels big, split per tool; each tool's wiring is independent.
