defmodule Server.Attention.Stall do
  @moduledoc """
  A coworker mid-turn whose pane has stopped changing is stuck where its thread cannot see it —
  the harness hung, a command is waiting on stdin, a network call never returns. This flags it:
  a `stall` message from `tlon` on the thread, opened when a window whose agent declared thinking
  (`Server.Presence.Thinking`) shows the same pane text for the band (`:attention_stall_ms`,
  default 5 minutes) and resolved when the pane moves or the window closes. Nothing is typed or
  killed: deciding whether to nudge, restart or wait is the operator's.

  A pane waiting on a dialog is `Server.Attention`'s prompt, not a stall. A frozen pane nobody is
  thinking in is idle. A standing-thread window (centre/tail, no `@funes_thread` tag) counts only
  its OWN agent's thinking — the window name is the coworker's handle — so an idle tail never
  inherits the lead's turn.

  `tick/2` takes and returns the pane memory `%{{workspace_id, window} => {hash, since}}`; the
  poller carries it. In-memory on purpose: a restart forgets when a pane last moved, which only
  delays a flag by one band — and leaves an open stall open until the pane really moves.
  """

  import Ecto.Query

  alias Server.Attention
  alias Server.Bus
  alias Server.Channel
  alias Server.Message
  alias Server.Presence.Thinking
  alias Server.Repo
  alias Server.Thread
  alias Server.Tmux
  alias Server.Workspaces

  @default_band_ms 5 * 60_000

  @doc "One pass over every workspace's windows. Opts: `now:`, `band_ms:`."
  def tick(panes, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    band = Keyword.get(opts, :band_ms, Application.get_env(:server, :attention_stall_ms, @default_band_ms))

    Workspaces.all()
    |> Enum.map(&tick_workspace(&1.id, panes, now, band))
    |> Enum.reduce(%{}, &Map.merge/2)
  end

  defp tick_workspace(workspace_id, panes, now, band) do
    standing = with %Thread{id: id} <- Channel.machine_thread(workspace_id), do: id

    seen =
      for tab <- Tmux.list_windows(workspace_id),
          tid = tab.thread_id || standing,
          is_integer(tid),
          into: %{},
          do: step(workspace_id, tid, tab, panes, now, band)

    for stall <- open_stalls(workspace_id),
        not Map.has_key?(seen, {workspace_id, stall.payload["window"]}),
        do: resolve(stall, "window closed")

    seen
  end

  defp step(workspace_id, tid, tab, panes, now, band) do
    key = {workspace_id, tab.name}
    hash = :erlang.phash2(capture(workspace_id, tab.index))
    open = open_stall(tid, tab.name)
    since = since(panes[key], hash, open, now)

    if is_nil(open) and DateTime.diff(now, since, :millisecond) >= band and
         thinking?(tid, tab) and is_nil(Attention.open_prompt(tid, tab.name)) do
      open(workspace_id, tid, tab.name, DateTime.diff(now, since, :minute))
    end

    {key, {hash, since}}
  end

  defp since({hash, since}, hash, _open, _now), do: since
  # first sight (a fresh poller) starts the clock; it is no evidence the pane moved
  defp since(nil, _hash, _open, now), do: now
  defp since(_moved, _hash, nil, now), do: now

  defp since(_moved, _hash, open, now) do
    resolve(open, "pane moved")
    now
  end

  defp capture(workspace_id, index) do
    case Tmux.run(workspace_id, ["capture-pane", "-p", "-t", Tmux.target(workspace_id, index)]) do
      {out, 0} when is_binary(out) -> out
      _ -> ""
    end
  end

  defp thinking?(thread_id, %{thread_id: nil, name: name}),
    do: Enum.any?(Thinking.thinking_for(thread_id), &(String.downcase(&1.agent) == String.downcase(name)))

  defp thinking?(thread_id, _leaf), do: Thinking.thinking_for(thread_id) != []

  # Delivered at birth: the row is the operator's to read; the switchboard must not type it into
  # the frozen pane.
  defp open(workspace_id, thread_id, window, minutes) do
    %{
      thread_id: thread_id,
      author: "tlon",
      kind: "stall",
      body: "⚠ stalled — #{window} is mid-turn and its pane has not changed for #{minutes}m",
      payload: %{"window" => window, "workspace_id" => workspace_id}
    }
    |> Message.post_changeset()
    |> Ecto.Changeset.put_change(:delivered_at, DateTime.truncate(DateTime.utc_now(), :second))
    |> Repo.insert!()
    |> tap(&Bus.broadcast({:message_posted, &1}))
  end

  defp resolve(stall, resolution) do
    stall
    |> Message.resolve_changeset(resolution)
    |> Repo.update!()
    |> tap(&Bus.broadcast({:prompt_resolved, &1}))
  end

  defp open_stall(thread_id, window) do
    Repo.one(
      from m in Message,
        where:
          m.thread_id == ^thread_id and m.kind == "stall" and is_nil(m.resolved_at) and
            fragment("? ->> 'window'", m.payload) == ^window,
        order_by: [desc: m.id],
        limit: 1
    )
  end

  defp open_stalls(workspace_id) do
    Repo.all(
      from m in Message,
        join: t in Thread,
        on: t.id == m.thread_id,
        where: t.workspace_id == ^workspace_id and m.kind == "stall" and is_nil(m.resolved_at)
    )
  end
end
