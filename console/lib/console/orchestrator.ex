defmodule Console.Orchestrator do
  @moduledoc """
  The tertius command line's brain (Slice 1): take a routed action (`Console.Orchestrator.Router`),
  execute it over the in-process funes contexts, and return a **receipt** — because a command line
  you talk into with no confirmation is the exact failure this repo opened on 2026-08-30 (a reply
  lost to a terminal). Safe verbs (post/note/ticket/query) dispatch straight; consequential ones
  (open work, approve a gate) return `{:confirm, summary}` and only fire through `confirm/2`.

  Everything routes through the exported `Server` facade + contexts (never `Repo` — the `:boundary`
  compiler enforces it). `ctx` is `%{workspace_id: id, operator: name}` — the focused workspace and
  who's speaking.
  """
  alias Console.Server.Channel
  alias Console.Server.Notes
  alias Console.Server.Tickets

  @doc "`:safe` (dispatch straight) or `:consequential` (confirm first). Pure."
  def classify({:open, _stage, _title}), do: :consequential
  def classify({:approve, _n}), do: :consequential
  def classify(_action), do: :safe

  @doc "Execute a safe action, or hand a consequential one back for confirmation. Returns `{:ok, receipt}`, `{:error, msg}`, or `{:confirm, summary}`."
  def dispatch({:post, handle, body}, ctx) do
    case thread_of(handle) do
      nil ->
        {:error, "no coworker @#{handle} leading an open thread"}

      tid ->
        {:ok, _} = Channel.post(%{thread_id: tid, author: ctx.operator, body: "@#{handle} #{body}"})
        {:ok, "→ posted to ##{tid} · woke @#{handle} ✓"}
    end
  end

  def dispatch({:note, body}, ctx) do
    case Notes.write(%{body: body, scope: "workspace", scope_id: ctx.workspace_id, author: ctx.operator}) do
      {:ok, n} -> {:ok, "→ noted ##{n.id} (workspace) ✓"}
      {:error, cs} -> {:error, changeset_error(cs)}
    end
  end

  def dispatch({:ticket, title}, ctx) do
    case Tickets.file(%{workspace_id: ctx.workspace_id, title: title}) do
      {:ok, t} -> {:ok, "→ filed ticket ##{t.id} in backlog ✓"}
      {:error, cs} -> {:error, changeset_error(cs)}
    end
  end

  def dispatch({:query, :roster}, _ctx) do
    Console.Server.staffed_machine_threads()
    |> Enum.map(& &1.lead)
    |> Enum.uniq()
    |> case do
      [] -> {:ok, "no coworkers leading an open thread"}
      names -> {:ok, "on the clock: " <> Enum.join(names, ", ")}
    end
  end

  def dispatch({:query, :blocked}, _ctx) do
    n = Enum.count(Console.Server.workline_statuses(), &(&1.awaiting not in [nil, ""]))
    {:ok, "#{n} thread#{if n == 1, do: "", else: "s"} awaiting you"}
  end

  def dispatch({:open, stage, title}, _ctx), do: {:confirm, "open #{stage_label(stage)} “#{title}”"}
  def dispatch({:approve, n}, _ctx), do: {:confirm, "approve ##{n}"}

  # No verb matched → passthrough: post the line to the machine (root) thread, so the tertius line is
  # a real conversation with the crew, not a strict command parser. (v2 hands it to the tertius agent
  # for smarter, LLM-interpreted intent — but a plain message is the honest default now.)
  def dispatch({:chat, text}, ctx) do
    case Channel.machine_thread(ctx.workspace_id) do
      %{id: id, title: title} ->
        {:ok, _} = Channel.post(%{thread_id: id, author: ctx.operator, body: text})
        {:ok, "→ posted to #{title} ✓"}

      _ ->
        {:error, "no machine thread to post to yet"}
    end
  end

  @doc "Fire a consequential action after the operator confirms."
  # No stage → an UNTRACKED plain thread (the `explore` verb): it stays plain unless the operator
  # tracks it. A stage → a WORKLINE opened AT that stage (any-stage entry, Slice 4D).
  def confirm({:open, nil, title}, ctx) do
    case Channel.open_thread(%{title: title, workspace_id: ctx.workspace_id}) do
      {:ok, t} -> {:ok, "→ opened ##{t.id} (untracked) “#{title}” ✓"}
      {:error, cs} -> {:error, changeset_error(cs)}
    end
  end

  def confirm({:open, stage, title}, ctx) do
    case Console.Server.open_workline(%{title: title, stage: stage, workspace_id: ctx.workspace_id}) do
      {:ok, t} -> {:ok, "→ opened ##{t.id} #{stage_label(stage)} “#{title}” ✓"}
      {:error, {:invalid_stage, s}} -> {:error, "can't open at stage #{s}"}
      {:error, cs} -> {:error, changeset_error(cs)}
    end
  end

  # Approving a parked gate advances the workline (Slice 4D): re-verifies the owed artifact, then
  # flips (spec→plan, review→merged, machine-born intent→spec). `n` is the thread id.
  def confirm({:approve, n}, _ctx) do
    case Console.Server.approve_workline(n) do
      {:ok, t} -> {:ok, "→ approved ##{n} → #{t.stage} ✓"}
      {:error, :no_thread} -> {:error, "no thread ##{n}"}
      {:error, :nothing_awaiting} -> {:error, "##{n} has no parked gate to approve"}
      {:error, {:artifact_missing, why}} -> {:error, "##{n} still owes: #{why}"}
      {:error, reason} -> {:error, "approve ##{n} failed: #{inspect(reason)}"}
    end
  end

  # -- helpers --------------------------------------------------------------

  # Resolve @handle → the open thread that agent leads, via the exported facade (never a raw query).
  # v1 scope: the staffed machine threads (where coworkers live); project-thread leads land in Slice 4.
  defp thread_of(handle) do
    case Enum.find(Console.Server.staffed_machine_threads(), &(&1.lead == handle)) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp changeset_error(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end

  defp stage_label(nil), do: "(untracked)"
  defp stage_label(stage), do: "[#{stage}]"
end
