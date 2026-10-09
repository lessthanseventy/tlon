defmodule Server.Tickets do
  @moduledoc """
  The tickets context (2026-08-30): the lightweight terminal tracker's write pipe + reads over
  the `ticket` table (the `local` backend). Workspace-scoped. Agents and the operator both file
  here (MCP `file_ticket`), and a filed ticket **promotes** into a thread when work starts. Every
  write announces on `Server.Bus`'s tickets topic so the board refreshes.

  Backend note: `local` is the only backend today. When a workspace points at Jira/GitHub, an
  adapter (under `adapters\/`) will implement the same file/list/update verbs behind a
  `TicketBackend` behaviour — introduced with that first adapter (YAGNI until a 2nd impl exists).
  """
  import Ecto.Query

  alias Server.Bus
  alias Server.Repo
  alias Server.Ticket
  alias Server.TicketLink
  alias Server.TicketThread

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

  @doc """
  Tickets in a workspace in BOARD order: `sort` descending, newest first as the tie-break. Higher
  `sort` sits nearer the top of its column — that is what `reorder/2` moves and what persists.
  """
  def in_workspace(workspace_id),
    do: Repo.all(from t in Ticket, where: t.workspace_id == ^workspace_id, order_by: [desc: t.sort, desc: t.id])

  @doc "Open (not-done) tickets in a workspace — the capture net minus the archive."
  def open_in_workspace(workspace_id) do
    Repo.all(
      from t in Ticket,
        where: t.workspace_id == ^workspace_id and t.status != "done",
        order_by: [desc: t.id]
    )
  end

  @doc "A ticket by id, or nil."
  def get(id), do: Repo.get(Ticket, id)

  @doc "Update a ticket's mutable fields. `{:ok, ticket}` or `{:error, changeset}`."
  def update(%Ticket{} = ticket, attrs) do
    result = ticket |> Ticket.update_changeset(attrs) |> Repo.update() |> Bus.announce(:ticket_updated)
    refresh_epic(epic_of(ticket.id))
    result
  end

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

  @doc "Promote a ticket into the thread it became (links it + moves it to `doing`)."
  def promote(%Ticket{} = ticket, thread_id) do
    with {:ok, _tie} <- tie(ticket, thread_id, "promoted") do
      result = ticket |> Ticket.start_changeset() |> Repo.update() |> Bus.announce(:ticket_updated)
      refresh_epic(epic_of(ticket.id))
      result
    end
  end

  @doc """
  A thread closed: every ticket started into it (`promoted`) that is not done yet is done now —
  unless the thread is a workline that never merged. Its work didn't land, so the ticket stays
  `doing`, and the Maintain sweep returns a `doing` ticket with no open thread to the backlog.
  """
  def done_for(thread_id) do
    case Repo.get(Server.Thread, thread_id) do
      %Server.Thread{stage: stage} when not is_nil(stage) and stage != "merged" -> :ok
      _ -> thread_id |> promoted(&(&1 != "done")) |> Enum.each(&__MODULE__.update(&1, %{status: "done"}))
    end
  end

  @doc "A merged workline came back (reopened, or its PR conflicted): its done tickets are `doing` again."
  def undone_for(thread_id) do
    thread_id |> promoted(&(&1 == "done")) |> Enum.each(&__MODULE__.update(&1, %{status: "doing"}))
  end

  defp promoted(thread_id, status?) do
    from(t in Ticket,
      join: tt in TicketThread,
      on: tt.ticket_id == t.id,
      where: tt.thread_id == ^thread_id and tt.kind == "promoted"
    )
    |> Repo.all()
    |> Enum.filter(&status?.(&1.status))
  end

  @doc """
  Send a ticket to its workspace's manager — the bench's meta coworker (the surveyor) — as intake
  on the workspace's root thread: an operator post that @mentions them with the ticket and asks
  them to staff it (`staff_child` with the `ticket_id`, which moves the ticket into the thread they
  open). The ticket is marked `todo`: handed over, not started. A workspace with no manager or no
  root thread starts the ticket with its lead instead. `{:ok, %{routed_to: name}}` or
  `{:ok, %{started: thread}}`, or `{:error, reason}`. An epic is never work: `{:error, :epic}`.
  """
  def route(%Ticket{kind: "epic"}), do: {:error, :epic}

  def route(%Ticket{} = ticket) do
    case {Server.Workspaces.manager(ticket.workspace_id), Server.Channel.machine_thread(ticket.workspace_id)} do
      {%Server.Coworker{name: name}, %Server.Thread{} = root} ->
        operator = Application.get_env(:server, :operator, "andrew")

        intake =
          Enum.join(
            Enum.reject(
              [
                "@#{name} intake — ticket ##{ticket.id}: #{ticket.title}",
                ticket.body,
                "Triage it: decide plain thread or workline, then staff_child whoever fits (with ticket_id: #{ticket.id}; a workline also takes workline: the stage to start at)."
              ],
              &(&1 in [nil, ""])
            ),
            "\n\n"
          )

        with {:ok, _} <- Server.Attention.respond(root.id, operator, intake),
             {:ok, _} <- __MODULE__.update(ticket, %{status: "todo"}) do
          {:ok, %{routed_to: name}}
        end

      _ ->
        with {:ok, thread} <- start_thread(ticket), do: {:ok, %{started: thread}}
    end
  end

  @doc """
  Start work on a ticket: a workline at build on the ticket's project (`Server.Workline.promote/1`,
  so it is verified, reviewed and risk-graded like any other) whose opening post is the ticket (the
  operator's post, so its lead is staffed like any ask), and the ticket promoted into it. `agent_id`
  hands the thread to that coworker; without one, or when it is the manager (who never leads a
  workline), the promotion staffs a builder — or, with none on the bench to staff, leaves it unled.
  `{:ok, thread}` or `{:error, reason}`; an epic is never work: `{:error, :epic}`.
  """
  def start_thread(ticket, agent_id \\ nil)
  def start_thread(%Ticket{kind: "epic"}, _agent_id), do: {:error, :epic}

  def start_thread(%Ticket{} = ticket, agent_id) do
    operator = Application.get_env(:server, :operator, "andrew")
    ask = Enum.join(Enum.reject([ticket.title, ticket.body, "(ticket ##{ticket.id})"], &(&1 in [nil, ""])), "\n\n")

    # a workline before the ask is posted, so its lead is briefed for the stage it starts at
    with {:ok, opened} <-
           %{title: ticket.title, workspace_id: ticket.workspace_id, project_id: ticket.project_id, scope: "machine"}
           |> then(&if(agent_id, do: Map.put(&1, :agent_id, agent_id), else: &1))
           |> Server.Channel.open_thread(),
         {:ok, thread} <- Server.Workline.promote(opened),
         {:ok, _} <- promote(ticket, thread.id),
         {:ok, _} <- Server.Attention.respond(thread.id, operator, ask) do
      {:ok, thread}
    end
  end

  @doc """
  Tie a ticket to a thread — `promoted` (work started here) or `relates`. Many-to-many: a ticket
  may be tied to several threads and a thread to several tickets. Tying twice with the same kind is
  idempotent, not an error, because the caller is usually a coworker re-reporting the same fact.
  """
  @spec tie(Ticket.t() | integer(), integer(), String.t()) :: {:ok, TicketThread.t()} | {:error, Ecto.Changeset.t()}
  def tie(ticket, thread_id, kind \\ "relates")
  def tie(%Ticket{id: id}, thread_id, kind), do: tie(id, thread_id, kind)

  def tie(ticket_id, thread_id, kind) do
    %{ticket_id: ticket_id, thread_id: thread_id, kind: kind}
    |> TicketThread.changeset()
    |> Repo.insert(on_conflict: :nothing)
    |> announce_ticket(ticket_id)
  end

  @doc "Untie a ticket from a thread. A tie that is not there is `:ok` — the end state is what was asked for."
  @spec untie(integer(), integer(), String.t()) :: :ok
  def untie(ticket_id, thread_id, kind) do
    Repo.delete_all(
      from(t in TicketThread, where: t.ticket_id == ^ticket_id and t.thread_id == ^thread_id and t.kind == ^kind)
    )

    announce_ticket({:ok, :untied}, ticket_id)
    :ok
  end

  @doc "The threads a ticket is tied to, as `{kind, thread_id}` — `promoted` first, then by tie age."
  @spec threads_of(integer()) :: [{String.t(), integer()}]
  def threads_of(ticket_id) do
    Repo.all(
      from(t in TicketThread,
        where: t.ticket_id == ^ticket_id,
        order_by: [asc: fragment("? <> ?", t.kind, "promoted"), asc: t.id],
        select: {t.kind, t.thread_id}
      )
    )
  end

  @doc "The tickets tied to a thread, as `{kind, ticket_id}` — the thread's side of the same table."
  @spec tickets_of_thread(integer()) :: [{String.t(), integer()}]
  def tickets_of_thread(thread_id) do
    Repo.all(
      from(t in TicketThread, where: t.thread_id == ^thread_id, order_by: [asc: t.id], select: {t.kind, t.ticket_id})
    )
  end

  @doc "Remove a ticket."
  def remove(%Ticket{} = ticket) do
    epic = epic_of(ticket.id)
    result = ticket |> Repo.delete() |> Bus.announce(:ticket_removed)
    refresh_epic(epic)
    result
  end

  @doc """
  Link one ticket to another: `blocks | relates | duplicates | parent`. Stored ONE way — there is
  no "blocked by" row, only `blocks` read from the other end — so the two directions cannot
  disagree. Linking twice is idempotent.
  """
  @spec link(integer(), integer(), String.t()) :: {:ok, TicketLink.t()} | {:error, Ecto.Changeset.t()}
  def link(from_id, to_id, kind \\ "relates") do
    %{from_id: from_id, to_id: to_id, kind: kind}
    |> TicketLink.changeset()
    |> Repo.insert(on_conflict: :nothing)
    |> announce_ticket(to_id)
    |> tap(fn result -> if kind == "parent" and match?({:ok, _}, result), do: refresh_epic(from_id) end)
  end

  @doc "Remove a link. One that is not there is `:ok` — the end state is what was asked for."
  @spec unlink(integer(), integer(), String.t()) :: :ok
  def unlink(from_id, to_id, kind) do
    Repo.delete_all(from(l in TicketLink, where: l.from_id == ^from_id and l.to_id == ^to_id and l.kind == ^kind))
    announce_ticket({:ok, :unlinked}, to_id)
    if kind == "parent", do: refresh_epic(from_id)
    :ok
  end

  @doc """
  Every link touching `ticket_id`, from BOTH ends, as `%{kind, direction, ticket_id}` — `direction`
  is `:out` for a link this ticket declared and `:in` for one pointing at it. `%{kind: "blocks",
  direction: :in}` IS "blocked by": the inverse read, not a second row.
  """
  @spec links_of(integer()) :: [%{kind: String.t(), direction: :in | :out, ticket_id: integer()}]
  def links_of(ticket_id) do
    out =
      from(l in TicketLink, where: l.from_id == ^ticket_id, select: %{kind: l.kind, ticket_id: l.to_id})
      |> Repo.all()
      |> Enum.map(&Map.put(&1, :direction, :out))

    incoming =
      from(l in TicketLink, where: l.to_id == ^ticket_id, select: %{kind: l.kind, ticket_id: l.from_id})
      |> Repo.all()
      |> Enum.map(&Map.put(&1, :direction, :in))

    out ++ incoming
  end

  @doc """
  The ids of the tickets blocking `ticket_id` that are NOT done — what the board turns into a
  blocked badge. A finished blocker does not block, which is why this filters on status rather than
  just reading the links.
  """
  @spec blockers(integer()) :: [integer()]
  def blockers(ticket_id) do
    Repo.all(
      from(l in TicketLink,
        join: t in Ticket,
        on: t.id == l.from_id,
        where: l.to_id == ^ticket_id and l.kind == "blocks" and t.status != "done",
        select: l.from_id
      )
    )
  end

  @doc """
  Blocked ids for a whole workspace in ONE query, as a MapSet — the board asks per frame, and a
  query per card is how a board gets slow.
  """
  @spec blocked_in_workspace(integer()) :: MapSet.t(integer())
  def blocked_in_workspace(workspace_id) do
    from(l in TicketLink,
      join: blocker in Ticket,
      on: blocker.id == l.from_id,
      join: blocked in Ticket,
      on: blocked.id == l.to_id,
      where: l.kind == "blocks" and blocker.status != "done" and blocked.workspace_id == ^workspace_id,
      select: l.to_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # A tie or a link changes what a TICKET means — whether it is blocked, which threads it belongs
  # to — so the event carries the ticket, never the join row. `Server.Bus` matches on the row struct
  # and keeping that set closed is what stops every subscriber having to know about join tables.
  defp announce_ticket({:ok, _row} = result, ticket_id) do
    case get(ticket_id) do
      %Ticket{} = ticket -> Bus.announce({:ok, ticket}, :ticket_updated)
      nil -> :ok
    end

    result
  end

  defp announce_ticket(result, _ticket_id), do: result

  @doc """
  Move a ticket up or down within its status column, and persist it. Swaps `sort` with the
  neighbour rather than renumbering the column, so a move is two writes whatever the column holds.
  `:ok` when there is no neighbour — the end of a list is not an error.
  """
  @spec reorder(Ticket.t(), :up | :down) :: :ok
  def reorder(%Ticket{} = ticket, direction) do
    case neighbour(ticket, direction) do
      %Ticket{} = other ->
        # The changesets directly, not `update/2`: `import Ecto.Query` brings its own `update/2`
        # into scope, and a reorder is ONE board change — announcing it twice would repaint twice.
        {:ok, moved} = ticket |> Ticket.update_changeset(%{sort: other.sort}) |> Repo.update()
        {:ok, _swapped} = other |> Ticket.update_changeset(%{sort: ticket.sort}) |> Repo.update()
        Bus.announce({:ok, moved}, :ticket_updated)
        :ok

      nil ->
        :ok
    end
  end

  # The ticket immediately above (`:up` — the next HIGHER sort) or below in the same column.
  defp neighbour(%Ticket{} = t, direction) do
    base = from(o in Ticket, where: o.workspace_id == ^t.workspace_id and o.status == ^t.status and o.id != ^t.id)

    case direction do
      :up -> base |> where([o], o.sort > ^t.sort) |> order_by([o], asc: o.sort) |> limit(1) |> Repo.one()
      :down -> base |> where([o], o.sort < ^t.sort) |> order_by([o], desc: o.sort) |> limit(1) |> Repo.one()
    end
  end

  # A new ticket lands at the TOP of its column — a 2-second capture you cannot see is a capture
  # that did not happen.
  defp next_sort(nil), do: 0

  defp next_sort(workspace_id) do
    (Repo.one(from t in Ticket, where: t.workspace_id == ^workspace_id, select: max(t.sort)) || 0) + 1
  end
end
