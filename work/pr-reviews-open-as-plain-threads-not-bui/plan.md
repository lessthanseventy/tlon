# Plan — PR reviews open as plain threads (#737)

Spec: `spec.md` beside this. One file changes (`server/lib/server/tickets.ex`), one test file
(`server/test/server/tickets_test.exs`). Three small commits. Run tests with
`~/projects/menard/bin/menard run test --in server test/server/tickets_test.exs`.
Commit trailer: `Co-Authored-By: <your model> <noreply@anthropic.com>`.

## Task 1 — failing test: a review ticket starts as a plain thread
File: `server/test/server/tickets_test.exs`, add after the test `"a started ticket is a workline at build ..."`
(inside the same `describe`):

```elixir
    test "a ticket labelled review starts as a plain thread: no stage, no slug, nothing owed" do
      {:ok, ws} = Workspaces.create(%{name: "Review"})

      {:ok, t} =
        Tickets.file(%{workspace_id: ws.id, title: "Review PR #675", body: "head abc123", labels: ["review"]})

      assert {:ok, %{stage: nil, slug: nil} = thread} = Tickets.start_thread(t)
      assert %{stage: nil, slug: nil} = Server.Repo.get!(Server.Thread, thread.id)
      assert Server.Workline.owed_status(thread) == :none

      assert [{"promoted", tid}] = Tickets.threads_of(t.id)
      assert tid == thread.id
      assert %{status: "doing"} = Tickets.get(t.id)

      assert [%{body: body}] = for(m <- Channel.thread_messages(thread), m.author == "andrew", do: m)
      assert body =~ "head abc123"
      assert body =~ "review_branch verdict"
      assert body =~ "ticket ##{t.id}"
    end
```
Done when: it fails (red) because the thread has `stage: "build"`. The existing build test
(`stage: "build"` for an unlabelled ticket) is the regression guard and stays green throughout.
Commit: `test: a review-labelled ticket should start as a plain thread (red)`.

## Task 2 — implement the branch in `Tickets.start_thread/2`
File: `server/lib/server/tickets.ex`. Edit `start_thread/2` (around line 271) and add two helpers.

Replace
```elixir
         {:ok, thread} <- Server.Workline.promote(opened),
         {:ok, _} <- promote(ticket, thread.id),
         {:ok, _} <- Server.Attention.respond(thread.id, operator, ask) do
```
with
```elixir
         {:ok, thread} <- begin_work(ticket, opened),
         {:ok, _} <- promote(ticket, thread.id),
         {:ok, _} <- Server.Attention.respond(thread.id, operator, ask(ticket, ask)) do
```
and add below `start_thread/2`:
```elixir
  @doc "Whether a ticket asks for a PR review: its labels include `review`, set by whoever filed it."
  def review?(%Ticket{labels: labels}), do: is_list(labels) and "review" in labels

  # A review's artifact is a review_branch verdict, not commits, so it is a plain thread (stage nil:
  # nothing owed, no nudge, no stuck alarm) — never a workline.
  defp begin_work(%Ticket{} = ticket, opened),
    do: if(review?(ticket), do: {:ok, opened}, else: Server.Workline.promote(opened))

  defp ask(%Ticket{} = ticket, ask) do
    if review?(ticket),
      do:
        ask <>
          "\n\nThis is a PR review, not a build: owed is a review_branch verdict (approve | request_changes) " <>
            "on the PR head sha you read. You write no code and own no work/<slug> branch.",
      else: ask
  end
```
Note the existing local variable is `ask`; the helper shares the name only as a function — if the
compiler warns about shadowing, rename the helper to `brief/2`.
Update the `start_thread/2` `@doc` first sentence: add "A ticket labelled `review` (`review?/1`) opens a
plain thread instead — no workline — owing a `review_branch` verdict on the PR head."
Done when: Task 1's test is green and the whole file passes
(`menard run test --in server test/server/tickets_test.exs`).
Commit: `Tickets.start_thread: a review-labelled ticket opens a plain thread, not a workline (#737)`.

## Task 3 — gate
Run `~/projects/menard/bin/menard run check --in server` (format, warnings-as-errors, tests) and
`menard run test --in server` for the boundary. Record with `record_check`. Then `push_branch`,
advance. If the root `AGENTS.md`/server docs mention "start always opens a workline",
update that line in the same commit as Task 2 (grep `start_thread` and `Tickets.start` in `docs/` and
`server/docs/spec.md`).
Done when: check exits 0.

## Out of scope
Auto-close on merge / finish refusal (#695), nag changes, migration, #569.
