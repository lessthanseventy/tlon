# Plan — #643 Uqbar routes the needs in its group

Source: ticket #643 (operator, msg #13555) and the tech lead's read (hronir, msg #13603). The
workline has no intent.md/spec.md; this plan is built from those two. Base: main at a2cc6ee. No
migration. Server code is under `server/`; run tests with `menard run test <file>`, the gate is
`mise run check`.

## Decisions (settled here)

1. **"Already paged" lives on Uqbar's study as a `chat` message from `tlon`** whose `payload` is
   `%{"need_page" => [key, ...]}`. Durable (survives restart), already visible to the operator on
   the study, needs no migration. Not an `event` row: `event.kind` is a DB CHECK, so a new kind is
   a migration, and the spec says none. Not process memory: lost on restart, re-pages everything.
2. **A key is paged iff a page message on the study is no older than the item** (`page.created_at
   >= item.at`) and lists the key. A newer item under a reused key (`item.at` later) pages again.
   Open, deliberate: an item the operator `overrule/1`s keeps its `at`, so it is not re-paged;
   Uqbar finds it in `operator_inbox` at its next check-in, and fail-open covers the rest.
3. **The pass runs in `Server.Jobs.Drain`** (every minute already). One post per workspace per
   pass. Skipped while Uqbar is mid-turn on its study (`Presence.Thinking.thinking_for/1` not
   empty) and within `@gap_s = 300` of the study's last page (the debounce). Both skips only delay:
   the keys stay unpaged and go in the next page. 5 min is well inside `uqbar_route_minutes` (30).
4. Fail-open and `uqbar_route_minutes` are untouched. Nothing here writes `need_routing`.

## Task 1 — operator_inbox carries key + route

Files: `server/lib/server/mcp/tools/operator_inbox.ex`, test in
`server/test/server/mcp/server_test.exs` (where the inbox is already tested; copy the fixture of
the neighbouring `operator_inbox` test, and for a `route: uqbar` item copy the setup of
`needs_test.exs:949-984`: `uqbar_routing` on, a conditional `question` ask).

Test first (red): with `uqbar_routing` on and one fresh `question` ask, the inbox entry has
`"key"` equal to `Needs.grouped().uqbar |> hd |> Map.fetch!(:key)` and `"route" => "uqbar"`; a
settled item (`Needs.settle/3` as `uqbar`) is absent; a `seats` item reads `"route" => "pass_up"`.

Change `execute/2` to render from `grouped/1`, uqbar group first, settled omitted (it is the
digest, not the inbox), and add the four fields:

```elixir
  def execute(_params, frame) do
    g = Server.Office.Needs.grouped()
    ok(frame, for(group <- ~w(uqbar phone machine clipboard)a, n <- g[group], do: render(n)))
  end

  defp render(n) do
    %{
      "key" => n.key,
      "route" => n.route,
      "recommendation" => n.recommendation,
      "why" => n.why,
      "kind" => n.kind,
      "level" => n.level,
      "thread_id" => n.thread_id,
      "title" => n.title,
      "text" => n.text,
      "asking" => n.thread_id && asking(n.thread_id)
    }
  end
```
Update the moduledoc: "from `Needs.grouped/1`: each item with its `key` and `route`; `route:
uqbar` items are Uqbar's to settle or pass up (`settle_need`, `pass_up_need`)".

Done: that test green; `menard run test test/server/mcp/server_test.exs` has 0 failures. Commit:
`inbox: operator_inbox carries each need's key and route, from grouped/1`.

## Task 2 — the role names the loop

Files: `server/lib/server/profiles.ex` (`@uqbar_role`, ~line 545), test in
`server/test/server/profiles_test.exs`.

Test first (red): the uqbar system prompt contains `operator_inbox`, `route: uqbar`,
`settle_need`, `pass_up_need`, `recommendation`, and each of `seats`, `quota`, `tool_denied`.

In THE CHECK-IN, drop the inbox clause (its approve-a-gate sentence moves below) and add its own
paragraph after it; keep the rest verbatim:

```
  THE INBOX LOOP. When you are woken for needs, and on every check-in: read operator_inbox. For
  each item with `route: uqbar`, decide by what Andrew has delegated and Needs.pass_up_rule says:
  settle_need (key, why: how it is handled) when it fits his standing calls and is reversible,
  inward and cheap; pass_up_need (key, why, recommendation: what you would do) when it is
  irreversible, outward, costly, needs a host command, or you are unsure. Seats, quota and a
  permission refusal (tool_denied) always reach him and are never yours to route: leave them. Every
  item you do not route reaches him as "Uqbar did not route it in time" after the
  uqbar_route_minutes knob (30), so route each one, do not skip. Approve a gate only after reading
  the diff and the review.
```
Done: test green. Commit: `uqbar role: read the inbox, settle or pass up each route: uqbar need`.

## Task 3 — the debounced wake

Files: new `server/lib/server/office/needs_page.ex`, new
`server/test/server/office/needs_page_test.exs`, `server/lib/server/jobs/drain.ex`.

Tests first (red), each building the Task 1 fixture (a fresh `question` ask in workspace `ws`,
`uqbar_routing` on, `Server.Outside.ensure_citizens/0`):
1. `run/0` posts ONE `tlon` message on `Outside.study(ws)` with `payload["need_page"]` = the key
   and a body containing `@uqbar`.
2. A second `run/0` posts nothing (key already paged).
3. Two new needs in one pass → one post naming both keys.
4. Uqbar mid-turn (`Presence.Thinking.thinking(study.id, "uqbar")`) → no post; after
   `Presence.Thinking.idle/2` and the gap passed (`run(DateTime.add(now, 301))`) → one post.
5. A new need within `@gap_s` of the last page → no post; after the gap → one post for it only.
6. A page older than the item (item.at later than the page's created_at) pages again.
7. `uqbar_routing` off → `grouped().uqbar` is empty → no post, no study opened.

Module:

```elixir
defmodule Server.Office.NeedsPage do
  @moduledoc """
  Wakes Uqbar on its study when a need newly enters its group (`Needs.grouped/1`'s `uqbar`). Needs
  are derived when read, so there is no insert to hook: a per-minute pass (`Server.Jobs.Drain`)
  posts ONE `tlon` message per workspace naming the keys not yet paged. "Paged" is that message's
  `payload["need_page"]`, no older than the item, so it survives a restart. Waits while Uqbar is
  mid-turn and `@gap_s` after its last page; the keys stay unpaged, so the next page carries them.
  """
  import Ecto.Query

  alias Server.{Channel, Message, Repo}
  alias Server.Office.Needs

  @gap_s 300
  @listed 20

  @doc "Page each workspace's Uqbar for its newly unrouted needs. `:ok`."
  def run(now \\ DateTime.utc_now()) do
    Needs.grouped(now).uqbar
    |> Enum.reject(&is_nil(&1.workspace_id))
    |> Enum.group_by(& &1.workspace_id)
    |> Enum.each(fn {ws, items} -> page(ws, items, now) end)
  end

  defp page(ws, items, now) do
    with {:ok, study} <- Server.Outside.study(ws),
         pages = pages(study.id),
         [_ | _] = fresh <- Enum.reject(items, &paged?(&1, pages)),
         true <- quiet?(study.id, pages, now) do
      keys = Enum.map(fresh, & &1.key)
      Channel.post(%{thread_id: study.id, author: "tlon", body: body(fresh), payload: %{"need_page" => keys}})
    end

    :ok
  end

  # `{created_at, keys}` of every page on the study, newest first
  defp pages(thread_id) do
    Repo.all(
      from m in Message,
        where: m.thread_id == ^thread_id and m.author == "tlon" and fragment("? \\? 'need_page'", m.payload),
        order_by: [desc: m.id],
        limit: 200,
        select: {m.created_at, m.payload}
    )
    |> Enum.map(fn {at, p} -> {at, p["need_page"]} end)
  end

  defp paged?(item, pages),
    do: Enum.any?(pages, fn {at, keys} -> item.key in keys and DateTime.compare(at, item.at) != :lt end)

  defp quiet?(thread_id, pages, now) do
    Server.Presence.Thinking.thinking_for(thread_id) == [] and
      case pages do
        [{at, _} | _] -> DateTime.diff(now, at) >= @gap_s
        [] -> true
      end
  end

  defp body(fresh) do
    listed = fresh |> Enum.take(@listed) |> Enum.map_join("\n", &"- #{&1.key} (#{&1.kind}) #{&1.title}")

    "@uqbar #{length(fresh)} new #{if length(fresh) == 1, do: "need waits", else: "needs wait"} in your group. " <>
      "Read operator_inbox, then settle_need or pass_up_need each `route: uqbar` item:\n" <> listed
  end
end
```
Check first: `server/lib/server/message.ex` (is `created_at` a `:utc_datetime`, does `post_changeset`
cast `payload`) — adjust the compare/attrs if not. In `Drain.perform/1` add
`_ = Server.Office.NeedsPage.run()` before the switchboard drain, and one line to its moduledoc.
Add one sentence to `Server.Office.Needs`'s Routing doc: "Uqbar is paged on its study when a key
enters the group (`Server.Office.NeedsPage`)".

Done: all 7 tests green; `menard run test test/server/office/needs_page_test.exs` and
`mise run check` pass. Commit: `needs: page Uqbar's study once when needs newly enter its group`.

## Task 4 — live check (after the PR lands and `release:cut` has restarted the service)

Not a code task. With `uqbar_routing` on (it is, live):
1. Raise a fresh conditional need: a seat's `ask_operator` (a `question`) on any open thread.
2. Within ~2 min a `tlon` post naming its key is on Uqbar's study:
   `psql tlon -c "select id, created_at, payload from message where author='tlon' and payload ? 'need_page' order by id desc limit 3"`.
3. Within `uqbar_route_minutes` (30) a row exists (0 rows ever before this change):
   `psql tlon -c "select key, state, why, at from need_routing order by at desc limit 3"`.
4. If settled, the item is in `Needs.grouped().settled` (the digest); if passed up, it is on the
   phone with Uqbar's recommendation, not "Uqbar did not route it in time".
Record it with `record_check` (cmd, exit, tail) on the thread.

## Out of scope
Backlog #581's non-prompt half; any change to `pass_up_rule/1`, the fail-open, or the knob.
