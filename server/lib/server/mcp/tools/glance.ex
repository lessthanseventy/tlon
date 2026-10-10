defmodule Server.MCP.Tool.OfficeGlance do
  @moduledoc """
  The office at a glance, from this session's seat — what its window shows beside the
  conversation (the tlon-citizen mod's band and toasts): the crew on its workspace and what each
  is doing, what is red on its own thread (open blockers, failed checks), its own voice (the
  persona's voice line and catchphrase), one line from the office's pool (a doorbell visitor, a pun),
  and the worklines that landed in the last day. Scoped to the caller's workspace and thread. A
  glance is not activity: the mod reads it on a timer, so it leaves warmth alone.
  """
  use Server.MCP.Tool

  import Ecto.Query, only: [from: 2]

  alias Server.Repo
  alias Server.Thread

  schema do
  end

  @impl true
  def execute(_params, frame) do
    identity = Identity.from_frame(frame, touch: false)
    thread = Repo.get(Thread, identity.thread_id)
    ok(frame, glance(thread, identity.agent))
  end

  defp glance(%Thread{workspace_id: ws} = thread, agent) when is_integer(ws) do
    seat = Enum.find(Server.Workspaces.bench_all(ws), &(&1.name == agent))

    %{
      archetype: seat && seat.archetype,
      crew: crew(ws, agent),
      red: red(ws, thread.id),
      persona: persona(ws, agent),
      line: line(ws),
      landed: landed(ws)
    }
  end

  defp glance(_thread, _agent), do: %{archetype: nil, crew: [], red: [], persona: nil, line: nil, landed: []}

  defp crew(ws, me) do
    turns = Server.Presence.Thinking.thinking_all()
    threads = MapSet.new(Repo.all(from(t in Thread, where: t.workspace_id == ^ws, select: t.id)))

    for r <- Server.Staff.roster(), r.agent != me, MapSet.member?(threads, r.thread_id), uniq: true do
      turn = Enum.find(Map.get(turns, r.thread_id, []), &(&1.agent == r.agent))
      %{agent: r.agent, thread_id: r.thread_id, warm: r.warm?, thinking: turn != nil, doing: turn && turn.doing}
    end
  catch
    :exit, _ -> []
  end

  defp red(ws, thread_id) do
    triage = Server.Office.Room.triage(ws)

    for item <- triage.blockers.shown ++ triage.failed_checks.shown, item.thread_id == thread_id, do: %{text: item.text}
  end

  defp persona(ws, agent) do
    case Server.Persona.get(ws, agent) do
      %{} = p -> %{voice: p["voice"], catchphrase: get_in(p, ["quirks", "catchphrase"])}
      _ -> nil
    end
  end

  defp line(ws) do
    case Server.ToyPool.visitors(ws) ++ Server.ToyPool.puns(ws) do
      [] -> nil
      lines -> lines |> Enum.random() |> to_line()
    end
  end

  defp to_line(%{} = visitor), do: visitor["line"] || visitor["text"] || nil
  defp to_line(line) when is_binary(line), do: line
  defp to_line(_), do: nil

  defp landed(ws) do
    for l <- Server.Librarian.landed_facts(ws, DateTime.add(DateTime.utc_now(), -1, :day)),
        do: %{thread_id: l.thread_id, title: l.title}
  end
end
