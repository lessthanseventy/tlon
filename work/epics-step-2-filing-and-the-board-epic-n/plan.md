# Plan — epics step 2: filing and the board data

Source: `docs/plans/2026-10-08-epics-and-initiatives-design.md` §3, §5 step 2 (step 1 is on main: `kind`, the parent law,
derived epic status, intake). Server + `scripts/tlon-cli.sh` only; no office/TUI (step 3). Read `server/AGENTS.md` first.
Paths are from the worktree root. Run tests from anywhere with Menard:
`~/projects/menard/bin/menard run test --in server test/server/epics_test.exs` (one run → parsed failures).
Gate before the last commit: `~/projects/menard/bin/menard run check --in server` (unsandboxed).
New tests go in the existing `server/test/server/epics_test.exs` (helpers `file/3`, `epic/3`, `setup` with `ws`) — each task
appends a `describe`. Commit per task; trailer `Co-Authored-By: <your model> …` per AGENTS.md.

Assumptions (say if wrong):
- "The board payload" = `Server.Office.Room` (the office's ticket data), served at `GET /api/office/…/:ws`. The existing
  flat `Room.tickets/1` / `/api/office/tickets/:ws` stay untouched (the office TUI reads them until step 3); the grouped
  read is a NEW `Room.board/1` at `/api/office/board/:ws`.
- Epic row = `done/total` over its children, its effective priority (higher of own and… an epic has no parent, so just its
  own priority — the *children's* effective priority is max(own, epic)), and its **next free child**: the lowest-`sort`
  (then lowest id) child that is `backlog`, not blocked by an unfinished ticket, not labelled `held` — exactly intake's
  "free" test.
- `epic_id` is for filing only (`Tickets.file`, MCP `file_ticket`, `POST /api/tickets`); not on `update_ticket`
  (`epic-add` / `Tickets.adopt` is the move-an-existing-ticket door).
- #212 (db guard on the parent law) is in flight on the same files; rebase onto it if it lands first, don't redo it.

---

## Task 1 — `Tickets.file` takes `epic_id`

Files: `server/lib/server/tickets.ex`, `server/test/server/epics_test.exs`.

1. Test first — append to `epics_test.exs`:

```elixir
  describe "filing into an epic" do
    test "epic_id files the ticket as the epic's child", %{ws: ws} do
      e = epic(ws, "Toy")
      t = file(ws, "step 1", %{epic_id: e.id})
      assert Tickets.epic_of(t.id) == e.id
    end

    test "a bad epic_id files nothing and says why", %{ws: ws} do
      plain = file(ws, "not an epic")
      before = length(Tickets.in_workspace(ws.id))
      assert {:error, cs} = Tickets.file(%{workspace_id: ws.id, title: "orphan", epic_id: plain.id})
      assert {:from_id, _} = List.keyfind(cs.errors, :from_id, 0)
      assert length(Tickets.in_workspace(ws.id)) == before
    end

    test "an epic cannot be filed under an epic", %{ws: ws} do
      e = epic(ws, "Toy")
      assert {:error, _} = Tickets.file(%{workspace_id: ws.id, title: "inner", kind: "epic", epic_id: e.id})
    end
  end
```

2. Run → red (epic_id is an unknown key, ticket filed loose; the 2nd test finds `{:ok, _}`).
3. Replace `file/1` in `tickets.ex` (keep the doc, add the epic_id sentence):

```elixir
  @doc """
  File a ticket. `{:ok, ticket}` or `{:error, changeset}`. With `epic_id` the ticket is filed as that epic's child in
  the same transaction, so a refused parent (not an epic, an epic under an epic) files nothing.
  """
  def file(attrs) do
    {epic_id, attrs} = attrs |> Map.new() |> Map.pop(:epic_id)

    attrs
    |> Map.put_new_lazy(:sort, fn -> next_sort(attrs[:workspace_id] || attrs["workspace_id"]) end)
    |> Ticket.file_changeset()
    |> insert_under(epic_id)
    |> Bus.announce(:ticket_filed)
  end

  defp insert_under(changeset, nil), do: Repo.insert(changeset)

  defp insert_under(changeset, epic_id) do
    Repo.transaction(fn ->
      with {:ok, ticket} <- Repo.insert(changeset),
           {:ok, _} <- link(epic_id, ticket.id, "parent") do
        ticket
      else
        {:error, cs} -> Repo.rollback(cs)
      end
    end)
  end
```

   (`link/3` already refreshes the epic's derived status; `Repo.rollback(cs)` makes the transaction return `{:error, cs}`.)
4. Done: the 3 tests green; the whole file green. Commit `feat(tickets): file a ticket straight into its epic`.

## Task 2 — `Tickets.adopt/2`: tie existing tickets to an epic, all or nothing

Files: `server/lib/server/tickets.ex`, `server/test/server/epics_test.exs`.

1. Test first:

```elixir
  describe "adopting tickets into an epic" do
    test "ties each ticket to the epic", %{ws: ws} do
      e = epic(ws, "Toy")
      [a, b] = [file(ws, "a"), file(ws, "b")]
      assert {:ok, [_, _]} = Tickets.adopt(e.id, [a.id, b.id])
      assert Tickets.epic_of(a.id) == e.id and Tickets.epic_of(b.id) == e.id
    end

    test "a ticket that already has another parent is refused, and nothing is tied", %{ws: ws} do
      [e1, e2] = [epic(ws, "One"), epic(ws, "Two")]
      [a, b] = [file(ws, "a"), file(ws, "b")]
      {:ok, _} = Tickets.adopt(e1.id, [b.id])
      assert {:error, {id, cs}} = Tickets.adopt(e2.id, [a.id, b.id])
      assert id == b.id
      assert {:to_id, {"already has a parent epic", _}} = List.keyfind(cs.errors, :to_id, 0)
      assert Tickets.epic_of(a.id) == nil
    end

    test "adopting what is already the epic's child is a no-op", %{ws: ws} do
      e = epic(ws, "Toy")
      a = file(ws, "a")
      {:ok, _} = Tickets.adopt(e.id, [a.id])
      assert {:ok, _} = Tickets.adopt(e.id, [a.id])
    end
  end
```

2. Run → red (`adopt/2` undefined).
3. Add to `tickets.ex` (next to `epic_of/1`):

```elixir
  @doc """
  Tie each of `ticket_ids` to the epic `epic_id` (a `parent` link). All or nothing: the first refusal rolls the rest
  back and is returned as `{:error, {ticket_id, changeset}}` so a caller can name the ticket. `{:ok, ticket_ids}`.
  """
  @spec adopt(integer(), [integer()]) :: {:ok, [integer()]} | {:error, {integer(), Ecto.Changeset.t()}}
  def adopt(epic_id, ticket_ids) do
    Repo.transaction(fn ->
      Enum.each(ticket_ids, fn id ->
        case link(epic_id, id, "parent") do
          {:ok, _} -> :ok
          {:error, cs} -> Repo.rollback({id, cs})
        end
      end)

      ticket_ids
    end)
  end
```

4. Done: tests green. Commit `feat(tickets): adopt — tie existing tickets to an epic, all or nothing`.

## Task 3 — `epic_id` on the MCP `file_ticket` (and the HTTP door), `epic_id` in the ticket brief

Files: `server/lib/server/mcp/tools/workspace.ex` (FileTicket schema, ~l.157), `server/lib/server/mcp/brief.ex` (`ticket/1`,
l.211), `server/lib/server/mcp/operator_api.ex` (`file_ticket/1` l.491 + its moduledoc line 70),
`server/test/server/mcp/server_test.exs` (next to the `file_ticket lands in…` test, l.882).

1. Test first — in `server_test.exs`, after the `file_ticket lands…` test:

```elixir
  test "file_ticket with epic_id files the ticket into that epic; a non-epic parent is refused" do
    {:ok, ws} = Server.Workspaces.register(%{name: "EpicWS"})
    {:ok, thread} = Channel.open_thread(%{title: "work", workspace_id: ws.id})
    {:ok, agent} = Staff.register_agent(%{name: "EpicFiler", mandate: "build", engine: "fresh"})
    token = MCP.Tokens.mint(thread, agent)
    session = handshake(token)
    {:ok, epic} = Server.Tickets.file(%{workspace_id: ws.id, title: "Toy", kind: "epic"})

    filed = token |> call(session, 2, "file_ticket", %{"title" => "step 1", "epic_id" => epic.id}) |> decode_tool_json()
    assert %{"epic_id" => epic_id} = filed
    assert epic_id == epic.id

    plain = token |> call(session, 3, "file_ticket", %{"title" => "loose"}) |> decode_tool_json()
    assert plain["epic_id"] == nil

    refused = token |> call(session, 4, "file_ticket", %{"title" => "bad", "epic_id" => plain["id"]})
    refute Server.Tickets.in_workspace(ws.id) |> Enum.any?(&(&1.title == "bad"))
    assert inspect(refused) =~ "only an epic can be a parent"
  end
```

   (If `call/…` returns a shape where the last assertion needs adjusting, assert on the error text the way the nearest
   existing refusal test in this file does.)
2. Run `… test --in server test/server/mcp/server_test.exs` → red.
3. `FileTicket` schema: add
   `field :epic_id, :integer, description: "File the ticket as a child of this epic (a ticket of kind epic), optional"`.
   `params` already flows into `Tickets.file/1`, which now understands `:epic_id` (Task 1). A nil `epic_id` must not
   break: `Map.pop` yields nil → plain insert.
4. `Brief.ticket/1`: add `"epic_id" => Server.Tickets.epic_of(t.id)`.
5. HTTP door: in `file_ticket/1` add `epic_id: b["epic_id"]` to the map handed to `Tickets.file`; and the
   `POST /api/tickets` moduledoc line gains `"epic_id"?`.
6. Done: the MCP test and the rest of `server_test.exs` green (the tool-list assertion is unchanged — no new tool).
   Commit `feat(mcp): file_ticket takes epic_id; a ticket names its epic`.

## Task 4 — `tlon-cli epic-new` / `epic-add`

Files: `scripts/tlon-cli.sh` (header usage l.24–32, two new cases beside `ticket-file` l.253, the usage line l.511),
`server/test/server/epics_test.exs`.

The CLI is thin rpc into the live node (see its header + `tlon_cli_test.exs`: never `System.halt`, a refusal `raise`s). The
logic is already tested in Tasks 1–2; add one static guard that the commands exist and one end-to-end of what they call.

1. Test first (append):

```elixir
  describe "tlon-cli epic filing" do
    @cli Path.expand("../../../scripts/tlon-cli.sh", __DIR__)

    test "epic-new and epic-add are commands, and are in the usage line" do
      src = File.read!(@cli)
      assert src =~ ~r/^  epic-new\)/m
      assert src =~ ~r/^  epic-add\)/m
      assert src =~ "|epic-new|epic-add|"
    end

    test "what epic-new calls files an epic; what epic-add calls refuses a second parent", %{ws: ws} do
      {:ok, e} = Tickets.file(%{workspace_id: ws.id, project_id: nil, title: "Toy", body: "", kind: "epic"})
      assert e.kind == "epic"
      t = file(ws, "a")
      {:ok, _} = Tickets.adopt(e.id, [t.id])
      other = epic(ws, "Other")
      assert {:error, {id, _}} = Tickets.adopt(other.id, [t.id])
      assert id == t.id
    end
  end
```

2. Run → red on the first test.
3. In `tlon-cli.sh` add, right after the `ticket-file)` case (copy its arg handling / `esc` / `int` helpers — read that case
   and the `ticket-set` case first, quoting is the only gotcha):

```bash
  epic-new)
    # File an epic: epic-new <workspace-id> <title> [body…]   (a ticket of kind epic; its design doc goes in the body)
    ws="${2:-}"; title="${3:-}"; shift 3 2>/dev/null || true
    int "$ws" && [ -n "$title" ] || { echo 'usage: tlon-cli.sh epic-new <workspace-id> <title> [body…]' >&2; exit 2; }
    exec "$SERVER" rpc "case Server.Tickets.file(%{workspace_id: $ws, kind: \"epic\", title: \"$(esc "$title")\", body: \"$(esc "$*")\"}) do {:ok, t} -> IO.puts(\"filed epic ##{t.id} — #{t.title}\"); {:error, cs} -> IO.puts(\"refused: #{inspect(cs.errors)}\"); raise(\"refused\") end"
    ;;
  epic-add)
    # Tie tickets to an epic (all or nothing): epic-add <epic-id> <ticket-id…>
    ep="${2:-}"; shift 2 2>/dev/null || true
    int "$ep" && [ "$#" -gt 0 ] || { echo 'usage: tlon-cli.sh epic-add <epic-id> <ticket-id…>' >&2; exit 2; }
    for tk in "$@"; do int "$tk" || { echo "not a ticket id: $tk" >&2; exit 2; }; done
    exec "$SERVER" rpc "case Server.Tickets.adopt($ep, [$(IFS=,; echo "$*")]) do {:ok, ids} -> IO.puts(\"epic #$ep now holds #{length(ids)} ticket(s)\"); {:error, {id, cs}} -> IO.puts(\"refused ##{id}: #{inspect(cs.errors)}\"); raise(\"refused\") end"
    ;;
```

   Add two header lines (`#   epic-new <ws> <title> [body…]  file an epic` / `#   epic-add <epic> <ticket…>  tie tickets
   to an epic (one parent each)`) and `epic-new|epic-add|` into the usage `{…}` list. Match how `ticket-file` sets `$ws`
   (the real script may parse args differently than the sketch above — follow it, not the sketch).
4. Done: `… test --in server test/server/epics_test.exs` green; `mise run check:names` green; by hand on a scratch node
   (`mise run server:dev`, MCP :4041) `epic-new` then `epic-add` prints the filed/holds lines and a second `epic-add` of the
   same ticket under another epic exits non-zero with `already has a parent epic`. Commit
   `feat(cli): tlon-cli epic-new and epic-add`.

## Task 5 — the board: epics with progress, children grouped, the rest loose

Files: `server/lib/server/ticket.ex` (+ `urgency/1`), `server/lib/server/intake.ex` (use it; `held?` public),
`server/lib/server/office/room.ex` (new `board/1` after `tickets/1`, l.225),
`server/test/server/office/room_test.exs`.

1. Test first — append to `room_test.exs` (reuse its `ctx.ws`):

```elixir
  describe "board: epics with progress" do
    setup ctx do
      mk = fn attrs -> elem(Tickets.file(Map.merge(%{workspace_id: ctx.ws.id}, attrs)), 1) end
      %{mk: mk}
    end

    test "groups children under their epic with done/total, and the rest as loose", %{ws: ws, mk: mk} do
      toy = mk.(%{title: "Toy", kind: "epic", priority: "high"})
      a = mk.(%{title: "a", epic_id: toy.id, sort: 1})
      b = mk.(%{title: "b", epic_id: toy.id, sort: 2})
      loose = mk.(%{title: "loose"})
      {:ok, _} = Tickets.update(a, %{status: "done"})

      %{epics: [row], loose: [l]} = Room.board(ws.id)
      assert %{id: toy_id, title: "Toy", done: 1, total: 2, priority: "high", status: "doing"} = row
      assert toy_id == toy.id
      assert Enum.map(row.children, & &1.id) == [a.id, b.id]
      assert l.id == loose.id
    end

    test "next is the lowest-sort free child: skips done, blocked and held", %{ws: ws, mk: mk} do
      e = mk.(%{title: "E", kind: "epic"})
      done = mk.(%{title: "done", epic_id: e.id, sort: 1})
      blocked = mk.(%{title: "blocked", epic_id: e.id, sort: 2})
      held = mk.(%{title: "held", epic_id: e.id, sort: 3, labels: ["held"]})
      free = mk.(%{title: "free", epic_id: e.id, sort: 4})
      blocker = mk.(%{title: "blocker"})
      {:ok, _} = Tickets.update(done, %{status: "done"})
      {:ok, _} = Tickets.link(blocker.id, blocked.id, "blocks")

      %{epics: [row]} = Room.board(ws.id)
      assert row.next == %{id: free.id, title: "free"}
      _ = held
    end

    test "an epic with nothing free has next nil; a child's effective priority is its epic's when higher", %{ws: ws, mk: mk} do
      e = mk.(%{title: "E", kind: "epic", priority: "high"})
      c = mk.(%{title: "c", epic_id: e.id, priority: "low"})
      {:ok, _} = Tickets.update(c, %{status: "done"})

      %{epics: [row]} = Room.board(ws.id)
      assert row.next == nil
      assert [%{effective_priority: "high"}] = row.children
    end

    test "epics order by effective urgency, then board order; no epics is just loose", %{ws: ws, mk: mk} do
      lo = mk.(%{title: "lo", kind: "epic", priority: "low"})
      hi = mk.(%{title: "hi", kind: "epic", priority: "high"})
      assert [hi.id, lo.id] == Enum.map(Room.board(ws.id).epics, & &1.id)
      assert %{epics: [], loose: []} = Room.board(elem(Server.Workspaces.create(%{name: "Empty"}), 1).id)
    end
  end
```

   (`Tickets` and `Room` aliases exist in that file already; add any that don't.)
2. Run `… test --in server test/server/office/room_test.exs` → red (`board/1` undefined).
3. `ticket.ex`: add and document

```elixir
  @urgency %{"high" => 0, "med" => 1, "low" => 2}

  @doc "A priority's rank, 0 the most urgent — lower sorts first. An unknown priority ranks as `med`."
  @spec urgency(t() | String.t()) :: non_neg_integer()
  def urgency(%__MODULE__{priority: priority}), do: urgency(priority)
  def urgency(priority), do: Map.get(@urgency, priority, 1)
```

   In `intake.ex`: delete `@urgency` (l.22) and the private `urgency/1`; call `Ticket.urgency/1` in `rank/2`; change
   `defp held?` to `def held?` with `@doc "Whether a ticket is parked by the `held` label — intake never starts it."`.
   Run `test/server/epics_test.exs` + `test/server/intake_test.exs` (if present) after this alone → still green (pure refactor).
4. `room.ex` — add (the module's `Tickets` alias exists; add `alias Server.{Intake, Ticket, TicketLink}` as needed, `import Ecto.Query` is already there if `Repo` queries are used elsewhere — otherwise add):

```elixir
  @doc """
  A workspace's backlog grouped by epic: `%{epics: [row], loose: [ticket]}`. Each epic row carries `done`/`total` over its
  children, its own `priority`, `status` (derived), its `children` (board order, each with `epic_id` and the
  `effective_priority` — the higher of its own and its epic's) and `next`: `%{id, title}` of its lowest-`sort` child that
  is `backlog`, unblocked and not held (what intake would start), or nil. Epics sort most urgent first, then board order.
  Tickets with no epic are `loose`. Flat reads stay in `tickets/1`.
  """
  @spec board(integer()) :: %{epics: [map()], loose: [map()]}
  def board(workspace_id) do
    all = Tickets.in_workspace(workspace_id)
    blocked = Tickets.blocked_in_workspace(workspace_id)
    by_id = Map.new(all, &{&1.id, &1})

    parent_of =
      Repo.all(
        from l in Server.TicketLink,
          join: e in Ticket,
          on: e.id == l.from_id,
          where: l.kind == "parent" and e.workspace_id == ^workspace_id,
          select: {l.to_id, l.from_id}
      )
      |> Map.new()

    {epics, tickets} = Enum.split_with(all, &(&1.kind == "epic"))
    {kids, loose} = Enum.split_with(tickets, &Map.has_key?(parent_of, &1.id))
    kids_of = Enum.group_by(kids, &parent_of[&1.id])

    rows =
      for e <- epics do
        children = Map.get(kids_of, e.id, [])
        free = children |> Enum.filter(&(&1.status == "backlog" and not MapSet.member?(blocked, &1.id) and not Intake.held?(&1)))
        next = Enum.min_by(free, &{&1.sort || 0, &1.id}, fn -> nil end)

        %{
          id: e.id,
          title: e.title,
          body: e.body,
          status: e.status,
          priority: e.priority,
          labels: e.labels,
          done: Enum.count(children, &(&1.status == "done")),
          total: length(children),
          next: next && %{id: next.id, title: next.title},
          children: Enum.map(children, &board_ticket(&1, by_id[parent_of[&1.id]], blocked))
        }
      end

    %{
      epics: Enum.sort_by(rows, &Ticket.urgency(&1.priority)),
      loose: Enum.map(loose, &board_ticket(&1, nil, blocked))
    }
  end

  defp board_ticket(t, epic, blocked) do
    %{
      id: t.id,
      title: t.title,
      status: t.status,
      priority: t.priority,
      effective_priority: Enum.min_by([t.priority | List.wrap(epic && epic.priority)], &Ticket.urgency/1),
      epic_id: epic && epic.id,
      blocked: MapSet.member?(blocked, t.id),
      held: Intake.held?(t)
    }
  end
```

   `Enum.sort_by` is stable, so equally urgent epics keep `in_workspace` (board) order. Simplify if the test pins less —
   delete a field no test or step 3 needs rather than keep it "just in case" (e.g. `body`, `labels` are kept: step 3's
   card and the initiative label on the row need them).
5. Done: `room_test.exs` + `epics_test.exs` green. Commit `feat(office): Room.board — epics with progress, children grouped, the rest loose`.

## Task 6 — serve it, and docs in the same commit

Files: `server/lib/server/mcp/operator_api.ex` (route l.273, moduledoc l.31), `server/lib/server/ticket.ex` moduledoc check,
`server/test/server/mcp/operator_api_test.exs` (find the file that already tests `/api/office/tickets` — `grep -rn
"office/tickets" server/test`; if none, put the test beside the nearest `/api/office/` one).

1. Test first: file an epic and a child, `GET /api/office/board/<ws>` → 200, JSON `epics[0].done == 0`, `total == 1`,
   `loose == []`; unknown workspace → the same 404 the sibling reads give.
2. Run → red (no route).
3. Add `board` to the `~w(activity triage memory tickets workspace schedules)` list (the route does
   `apply(Room, String.to_existing_atom(read), [&1.id])`, so `Room.board/1` is the whole implementation) and a moduledoc line
   `GET    /api/office/board/:ws        Office.Room.board (the backlog grouped by epic, with progress)`.
4. Docs: `Server.Ticket`'s moduledoc already says epics exist; add nothing unless it lists filing doors. If
   `server/AGENTS.md` or `adapters/AGENTS.md` lists tlon-cli commands or MCP ticket fields, add `epic-new`/`epic-add`/`epic_id`
   (`grep -rn "ticket-file" --include=*.md .`).
5. Done: whole gate green: `~/projects/menard/bin/menard run check --in server` and `mise run check:names` (names gate sees the
   new `Server.Tickets.adopt`/`Room.board` references). Commit `feat(api): /api/office/board — the grouped backlog`.

## Out of scope (named, not forgotten)
- Office screens, `enter` on an epic, the card's epic line — step 3. It will consume `/api/office/board/:ws`.
- The six-epic backfill and the `initiative` label display — step 4 (a label already rides on the row as `labels`).
- `epic_id` on `update_ticket` (re-parenting), un-adopting from the CLI (`Tickets.unlink/3` exists if ever needed).
