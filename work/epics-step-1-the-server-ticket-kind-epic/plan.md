# Plan — epics step 1: the server

Source: `docs/plans/2026-10-08-epics-and-initiatives-design.md` §2, §5 step 1. Server only (no CLI/MCP/office —
those are steps 2–4). Read `server/AGENTS.md` first. All paths relative to the worktree root; run from `server/`.

Test loop (one run, parsed failures): `~/projects/menard/bin/menard run test --in server test/server/epics_test.exs`
Gate before the last commit: `~/projects/menard/bin/menard run check --in server` (run unsandboxed).
New tests all live in ONE new file, `server/test/server/epics_test.exs`; each task appends a `describe`.
Edit Elixir with Menard verbs where they fit; plain `Edit` is fine for these small additions.

Decisions (assumptions, say if wrong):
- Epic status is **stored** in the existing `status` column and recomputed (`Tickets.refresh_epic/1`) after every write
  that can change it: child status update, child promote, parent link/unlink, child remove. No new column.
- A child counts as "started" when `doing` or `done` (a routed `todo` child has not started).
- An epic with no children is `backlog` (never `done`).
- The parent law lives in `TicketLink.changeset/1` (it does the two lookups), so `Tickets.link/3` and anything else
  that builds the changeset refuse alike.
- Intake: each epic contributes only its lowest-`sort` unblocked backlog child; then min over
  `{effective urgency, child-of-a-doing-epic first, newest-first}`.

---

## Task 1 — `kind` on ticket (migration + schema)

Files: `server/priv/repo/migrations/20261009000000_ticket_kind.exs` (new), `server/lib/server/ticket.ex`,
`server/test/server/epics_test.exs` (new).

1. **Test first** — create `server/test/server/epics_test.exs`:

```elixir
defmodule Server.EpicsTest do
  # Epics (design 2026-10-08): a ticket of kind "epic" holds other tickets via `parent` links and is never work.
  use ExUnit.Case, async: false

  alias Server.Intake
  alias Server.Repo
  alias Server.Ticket
  alias Server.Tickets

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Epics"})
    %{ws: ws}
  end

  defp file(ws, title, attrs \\ %{}),
    do: elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: title}, attrs)), 1)

  defp epic(ws, title, attrs \\ %{}), do: file(ws, title, Map.put(attrs, :kind, "epic"))

  describe "kind" do
    test "defaults to ticket and can be filed as epic", %{ws: ws} do
      assert file(ws, "plain").kind == "ticket"
      assert epic(ws, "Toy").kind == "epic"
    end

    test "a kind outside the set is a changeset error, and the DB refuses it too", %{ws: ws} do
      assert {:error, cs} = Tickets.file(%{workspace_id: ws.id, title: "x", kind: "story"})
      assert {:kind, _} = List.keyfind(cs.errors, :kind, 0)

      assert_raise Postgrex.Error, ~r/ticket_kind_check/, fn ->
        Repo.query!("UPDATE ticket SET kind = 'story' WHERE id = $1", [file(ws, "y").id])
      end
    end

    test "kind cannot be changed by update", %{ws: ws} do
      t = file(ws, "plain")
      {:ok, t} = Tickets.update(t, %{kind: "epic"})
      assert t.kind == "ticket"
    end
  end
end
```

2. Run it → red (`kind` unknown).
3. Migration `server/priv/repo/migrations/20261009000000_ticket_kind.exs`:

```elixir
defmodule Server.Repo.Migrations.TicketKind do
  use Ecto.Migration

  # an epic is a ticket that holds other tickets (epics design §2); the closed set is CHECK'd like status/priority
  def change do
    execute(
      "ALTER TABLE ticket ADD COLUMN kind TEXT NOT NULL DEFAULT 'ticket' CONSTRAINT ticket_kind_check CHECK (kind IN ('ticket','epic'))",
      "ALTER TABLE ticket DROP COLUMN kind"
    )
  end
end
```

4. `server/lib/server/ticket.ex`:
   - add `@kinds ~w(ticket epic)`; in the schema add `field :kind, :string, default: "ticket"` (after `:body`);
   - in `file_changeset/1` cast list: `[:workspace_id, :kind, :backend, :external_key, :external_url | @mutable]`
     (kind is NOT in `@mutable`, so update can't change it);
   - in `validate_sets/1` add `|> validate_inclusion(:kind, @kinds)`.
   - Moduledoc: replace "(GitHub-Issues-light, no epics/sprints/ceremony)" with "(GitHub-Issues-light, no sprints/ceremony)" and
     add a paragraph: "`kind` is `ticket` or `epic`. An epic holds other tickets through `parent` links (stored `from = epic, to =
     child`; one parent per ticket, no epic under an epic — `Server.TicketLink`), is never work (`Server.Intake` skips it,
     `Server.Tickets.start_thread/2` refuses it), and its `status` is derived from its children (`Server.Tickets.refresh_epic/1`)."
5. Green: the epics_test file. Commit: `feat(ticket): kind — ticket or epic, DB-CHECK'd`.

Done = 3 tests green + `mix ecto.migrate` clean (the test DB migrates on run).

## Task 2 — the parent law (one parent, no epic under an epic)

Files: `server/lib/server/ticket_link.ex`, `server/test/server/epics_test.exs`.

1. **Test first** — add to epics_test.exs:

```elixir
  describe "the parent law" do
    test "an epic adopts a ticket; read both ways", %{ws: ws} do
      e = epic(ws, "Toy")
      c = file(ws, "child")
      assert {:ok, _} = Tickets.link(e.id, c.id, "parent")
      assert [%{kind: "parent", direction: :out, ticket_id: cid}] = Tickets.links_of(e.id)
      assert cid == c.id
      assert [%{kind: "parent", direction: :in}] = Tickets.links_of(c.id)
    end

    test "a second parent is refused", %{ws: ws} do
      e1 = epic(ws, "One")
      e2 = epic(ws, "Two")
      c = file(ws, "child")
      {:ok, _} = Tickets.link(e1.id, c.id, "parent")
      assert {:error, cs} = Tickets.link(e2.id, c.id, "parent")
      assert {"already has a parent epic", _} = cs.errors[:to_id]
    end

    test "adopting twice into the same epic stays idempotent", %{ws: ws} do
      e = epic(ws, "Toy")
      c = file(ws, "child")
      {:ok, _} = Tickets.link(e.id, c.id, "parent")
      assert {:ok, _} = Tickets.link(e.id, c.id, "parent")
    end

    test "no epic under an epic, and only an epic is a parent", %{ws: ws} do
      outer = epic(ws, "Outer")
      inner = epic(ws, "Inner")
      plain = file(ws, "plain")
      other = file(ws, "other")
      assert {:error, cs} = Tickets.link(outer.id, inner.id, "parent")
      assert {"an epic cannot have a parent", _} = cs.errors[:to_id]
      assert {:error, cs} = Tickets.link(plain.id, other.id, "parent")
      assert {"only an epic can be a parent", _} = cs.errors[:from_id]
    end
  end
```

2. Red. 3. In `ticket_link.ex`: add `alias Server.Repo`, `alias Server.Ticket`, `import Ecto.Query`; in `changeset/1`
   pipeline add `|> validate_parent_law()` after `validate_not_self()`; append:

```elixir
  # The epics law needs the two tickets, so it looks them up here; a missing ticket is left to the FK constraint.
  defp validate_parent_law(changeset) do
    with "parent" <- get_field(changeset, :kind),
         from_id when is_integer(from_id) <- get_field(changeset, :from_id),
         to_id when is_integer(to_id) <- get_field(changeset, :to_id) do
      changeset
      |> only_an_epic_parents(Repo.get(Ticket, from_id))
      |> an_epic_has_no_parent(Repo.get(Ticket, to_id))
      |> one_parent(from_id, to_id)
    else
      _ -> changeset
    end
  end

  defp only_an_epic_parents(changeset, %Ticket{kind: kind}) when kind != "epic",
    do: add_error(changeset, :from_id, "only an epic can be a parent")

  defp only_an_epic_parents(changeset, _), do: changeset

  defp an_epic_has_no_parent(changeset, %Ticket{kind: "epic"}),
    do: add_error(changeset, :to_id, "an epic cannot have a parent")

  defp an_epic_has_no_parent(changeset, _), do: changeset

  defp one_parent(changeset, from_id, to_id) do
    other_parent? =
      Repo.exists?(from l in __MODULE__, where: l.kind == "parent" and l.to_id == ^to_id and l.from_id != ^from_id)

    if other_parent?, do: add_error(changeset, :to_id, "already has a parent epic"), else: changeset
  end
```

   Update the moduledoc with one line: "A `parent` link runs `epic → child`; the changeset refuses a non-epic parent, an epic child and a second parent."
4. Green. Commit: `feat(ticket): the parent law — one parent, no epic under an epic`.

Done = the 4 tests green.

## Task 3 — an epic is never started or routed

Files: `server/lib/server/tickets.ex`, `server/test/server/epics_test.exs`.

1. **Test first**:

```elixir
  describe "an epic is never work" do
    test "start_thread and route refuse it", %{ws: ws} do
      e = epic(ws, "Toy")
      assert {:error, :epic} = Tickets.start_thread(e)
      assert {:error, :epic} = Tickets.route(e)
      assert Tickets.get(e.id).status == "backlog"
    end
  end
```

2. Red. 3. In `tickets.ex` add clauses ABOVE the existing heads:
   - `def route(%Ticket{kind: "epic"}), do: {:error, :epic}` before `def route(%Ticket{} = ticket) do`
   - for `start_thread/2` (has a default arg, so add a bodiless head first):

```elixir
  def start_thread(ticket, agent_id \\ nil)
  def start_thread(%Ticket{kind: "epic"}, _agent_id), do: {:error, :epic}
  def start_thread(%Ticket{} = ticket, agent_id) do
```
   (replace the old `def start_thread(%Ticket{} = ticket, agent_id \\ nil) do` line). Add to both `@doc`s: "An epic is never work: `{:error, :epic}`."
4. Check the two callers still render an atom error without crashing: `lib/server/mcp/tools/workspace.ex:259` and
   `lib/server/mcp/operator_api.ex:478` (read the `{:error, reason}` branch; if it does `inspect`/string-interpolates fine, otherwise
   add `:epic` → "an epic is never started; start one of its children"). Add a one-line test only if you changed a caller.
5. Green + `~/projects/menard/bin/menard run test --in server test/server/tickets_test.exs`. Commit: `feat(tickets): an epic is never started or routed`.

## Task 4 — derived epic status

Files: `server/lib/server/ticket.ex`, `server/lib/server/tickets.ex`, `server/test/server/epics_test.exs`.

1. **Test first**:

```elixir
  describe "derived epic status" do
    setup %{ws: ws} do
      e = epic(ws, "Toy")
      [a, b] = for t <- ["a", "b"], do: file(ws, t)
      for c <- [a, b], do: {:ok, _} = Tickets.link(e.id, c.id, "parent")
      %{e: e, a: a, b: b}
    end

    defp status(e), do: Tickets.get(e.id).status

    test "backlog until a child starts, doing after, done when the last child closes", %{e: e, a: a, b: b} do
      assert status(e) == "backlog"
      {:ok, a} = Tickets.update(a, %{status: "todo"})
      assert status(e) == "backlog"
      {:ok, a} = Tickets.update(a, %{status: "doing"})
      assert status(e) == "doing"
      {:ok, a} = Tickets.update(a, %{status: "done"})
      assert status(e) == "doing"
      {:ok, _} = Tickets.update(b, %{status: "done"})
      assert status(e) == "done"
      assert Tickets.get(e.id).closed_at
      _ = a
    end

    test "promote starts the epic; a reopened or added child sends it back to doing", %{ws: ws, e: e, a: a, b: b} do
      {:ok, _} = Tickets.update(a, %{status: "done"})
      {:ok, b} = Tickets.update(b, %{status: "done"})
      assert status(e) == "done"
      {:ok, _} = Tickets.update(b, %{status: "doing"})
      assert status(e) == "doing"
      {:ok, _} = Tickets.update(b, %{status: "done"})
      assert status(e) == "done"
      c = file(ws, "late addition")
      {:ok, _} = Tickets.link(e.id, c.id, "parent")
      assert status(e) == "doing"
      Tickets.remove(c)
      assert status(e) == "done"
    end

    test "unlinking the only unfinished child can close the epic; an epic with no children is backlog", %{ws: ws, e: e, a: a, b: b} do
      {:ok, _} = Tickets.update(a, %{status: "done"})
      :ok = Tickets.unlink(e.id, b.id, "parent")
      assert status(e) == "done"
      :ok = Tickets.unlink(e.id, a.id, "parent")
      assert status(e) == "backlog"
      assert status(epic(ws, "Empty")) == "backlog"
    end
  end
```

   (Remove the stray `_ = a` / unused-var noise when writing — the compiler gate is warnings-as-errors.)
2. Red. 3. `ticket.ex` — add:

```elixir
  @doc "An epic's status from its children's: `done` when all are done, `doing` once one has started, else `backlog`."
  @spec epic_status([String.t()]) :: String.t()
  def epic_status([]), do: "backlog"

  def epic_status(statuses) do
    cond do
      Enum.all?(statuses, &(&1 == "done")) -> "done"
      Enum.any?(statuses, &(&1 in ~w(doing done))) -> "doing"
      true -> "backlog"
    end
  end

  @doc "Set an epic's derived status (stamps `closed_at` like any status change)."
  def derive_changeset(%__MODULE__{} = epic, status) do
    epic
    |> change(status: status)
    |> stamp_closed()
    |> put_change(:updated_at, DateTime.truncate(DateTime.utc_now(), :second))
  end
```

4. `tickets.ex` — add the refresh and wire it:

```elixir
  @doc """
  Re-derive the status of the epic `epic_id` from its children (`Ticket.epic_status/1`), announcing a change.
  A no-op for nil or a ticket that is not an epic. Called after every write that can move a child's status or
  membership; it writes the epic directly, never through `update/2`, so it cannot recurse.
  """
  @spec refresh_epic(integer() | nil) :: :ok
  def refresh_epic(nil), do: :ok

  def refresh_epic(epic_id) do
    with %Ticket{kind: "epic"} = epic <- get(epic_id) do
      statuses =
        Repo.all(
          from l in TicketLink,
            join: c in Ticket,
            on: c.id == l.to_id,
            where: l.from_id == ^epic_id and l.kind == "parent",
            select: c.status
        )

      derived = Ticket.epic_status(statuses)

      if derived != epic.status,
        do: epic |> Ticket.derive_changeset(derived) |> Repo.update() |> Bus.announce(:ticket_updated)
    end

    :ok
  end

  @doc "The epic a ticket belongs to (its `parent` link's `from`), or nil."
  @spec epic_of(integer()) :: integer() | nil
  def epic_of(ticket_id),
    do: Repo.one(from l in TicketLink, where: l.to_id == ^ticket_id and l.kind == "parent", select: l.from_id)
```

   Wire-in (each keeps its return value):
   - `update/2`: `result = ticket |> Ticket.update_changeset(attrs) |> Repo.update() |> Bus.announce(:ticket_updated); refresh_epic(epic_of(ticket.id)); result`
   - `promote/2`: same wrap around the `start_changeset` update inside the `with`.
   - `remove/1`: `epic = epic_of(ticket.id)` BEFORE delete; after, `refresh_epic(epic)`; return the delete result.
   - `link/3` and `unlink/3`: when `kind == "parent"`, `refresh_epic(from_id)` after success (for `link`, only on `{:ok, _}`).
   Keep `Bus.announce` return shapes unchanged (`{:ok, ticket}`/`{:error, cs}`).
5. Green: epics_test + `tickets_test.exs`. Commit: `feat(tickets): an epic's status is derived from its children`.

## Task 5 — intake: skip epics, effective priority, finish what's started, step order

Files: `server/lib/server/intake.ex`, `server/test/server/epics_test.exs`.

1. **Test first**:

```elixir
  describe "intake" do
    defp adopt(e, c), do: {:ok, _} = Tickets.link(e.id, c.id, "parent")

    test "never picks an epic", %{ws: ws} do
      epic(ws, "Toy", %{priority: "high"})
      assert Intake.next(ws.id) == nil
    end

    test "a child inherits a high epic over a med loose ticket", %{ws: ws} do
      e = epic(ws, "Toy", %{priority: "high"})
      c = file(ws, "child")
      adopt(e, c)
      _loose = file(ws, "loose newer")
      assert Intake.next(ws.id).id == c.id
    end

    test "an epic's own priority never lowers a child's", %{ws: ws} do
      e = epic(ws, "Toy", %{priority: "low"})
      c = file(ws, "child", %{priority: "high"})
      adopt(e, c)
      _loose = file(ws, "loose", %{priority: "med"})
      assert Intake.next(ws.id).id == c.id
    end

    test "within an epic the lowest sort goes first, not the newest", %{ws: ws} do
      e = epic(ws, "Toy")
      first = file(ws, "step 1", %{sort: 1})
      second = file(ws, "step 2", %{sort: 2})
      third = file(ws, "step 3", %{sort: 3})
      for c <- [third, first, second], do: adopt(e, c)
      assert Intake.next(ws.id).id == first.id
      {:ok, _} = Tickets.update(first, %{status: "done"})
      assert Intake.next(ws.id).id == second.id
    end

    test "equally urgent: the child of a doing epic beats a newer loose ticket and an unstarted epic's child", %{ws: ws} do
      started = epic(ws, "Started")
      started_done = file(ws, "s1", %{sort: 1})
      started_next = file(ws, "s2", %{sort: 2})
      adopt(started, started_done)
      adopt(started, started_next)
      {:ok, _} = Tickets.update(started_done, %{status: "done"})
      assert Tickets.get(started.id).status == "doing"

      fresh = epic(ws, "Fresh")
      fresh_child = file(ws, "f1", %{sort: 99})
      adopt(fresh, fresh_child)
      _loose = file(ws, "loose newest", %{sort: 100})

      assert Intake.next(ws.id).id == started_next.id
    end

    test "loose tickets keep newest-first and a blocked step is skipped", %{ws: ws} do
      old = file(ws, "old")
      new = file(ws, "new")
      assert Intake.next(ws.id).id == new.id

      e = epic(ws, "Toy", %{priority: "high"})
      s1 = file(ws, "s1", %{sort: 1})
      s2 = file(ws, "s2", %{sort: 2})
      adopt(e, s1)
      adopt(e, s2)
      {:ok, _} = Tickets.link(s1.id, s2.id, "blocks")
      assert Intake.next(ws.id).id == s1.id
      _ = old
    end
  end
```

   (Again drop unused vars so warnings-as-errors passes. Move `defp adopt` above the describe if the compiler warns about defp placement.)
2. Red. 3. `intake.ex` — replace `next/1` and add helpers:

```elixir
  def next(ws) do
    blocked = Server.Tickets.blocked_in_workspace(ws)
    epics = epics_of(ws)

    from(t in Ticket, where: t.workspace_id == ^ws and t.status == "backlog" and t.kind == "ticket")
    |> Repo.all()
    |> Enum.reject(&(MapSet.member?(blocked, &1.id) or held?(&1)))
    |> first_step_of_each_epic(epics)
    |> Enum.min_by(&rank(&1, epics), fn -> nil end)
  end

  # %{child_id => epic}: which epic (if any) each ticket of the workspace belongs to
  defp epics_of(ws) do
    from(l in Server.TicketLink,
      join: e in Ticket,
      on: e.id == l.from_id,
      where: l.kind == "parent" and e.workspace_id == ^ws,
      select: {l.to_id, e}
    )
    |> Repo.all()
    |> Map.new()
  end

  # step order inside an epic: only its lowest-sort candidate may compete with the rest
  defp first_step_of_each_epic(tickets, epics) do
    {children, loose} = Enum.split_with(tickets, &Map.has_key?(epics, &1.id))

    firsts =
      children
      |> Enum.group_by(&epics[&1.id].id)
      |> Enum.map(fn {_epic, steps} -> Enum.min_by(steps, &{&1.sort || 0, &1.id}) end)

    loose ++ firsts
  end

  # effective priority = the higher of the ticket's and its epic's; a doing epic's child goes before the rest
  defp rank(ticket, epics) do
    epic = epics[ticket.id]
    urgency = Enum.min([urgency(ticket) | List.wrap(epic && urgency(epic))])
    {urgency, if(epic && epic.status == "doing", do: 0, else: 1), -(ticket.sort || 0), -ticket.id}
  end

  defp urgency(%Ticket{priority: priority}), do: Map.get(@urgency, priority, 1)
```

   Update `next/1`'s `@doc` and the moduledoc: "…an epic is never routed; its children are, by the higher of their own and their epic's priority,
   the children of an epic already `doing` first, each epic's lowest-`sort` step before its later ones; loose tickets newest-first."
4. Green: epics_test + `intake_test.exs`. Commit: `feat(intake): skip epics, inherit epic priority, finish started epics in step order`.

## Task 6 — gate and docs sweep

Files: `server/docs/spec.md` / `server/AGENTS.md` only if they describe tickets or intake (grep `-i "no epics\|epic"`; today
neither does — leave them alone if so).

1. `grep -rn -i "no epics" server/ docs/ --include=*.ex --include=*.md` → nothing stale left.
2. `~/projects/menard/bin/menard run check --in server` (unsandboxed) and `mise run check` → green. Fix anything the gate finds
   (format, warnings) in the task whose code it names, as a fixup commit on top.
3. Done = both green; `git log --oneline main..` shows five small commits; the five tests named in the design's §5 step 1 check
   (intake never routes an epic; child inherits a high epic; lowest sort first; last child done closes the epic; second parent and
   epic-under-epic refused) each map to a test above.

Out of scope (steps 2–4): `tlon-cli epic-new/epic-add`, `epic_id` on MCP tools, board payload, office screens, backfill.
