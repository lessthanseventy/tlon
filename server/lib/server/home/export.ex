defmodule Server.Home.Export do
  @moduledoc """
  The operator's whole home as the house's own list keeps it (`house/local_list.gd`): every jot of
  the home's messenger, done and dropped ones too, every agenda, person and the door, the open
  proposals, the two times the list and the morning message go out and the paired chat's id
  (`telegram_chat`, "" when none). Read-only: nothing is
  changed or deleted here. Ids are the server's own; the importer maps them.

  `counts` is what the importer prints beside its own: jots by kind, piles by kind, proposals.
  """
  import Ecto.Query

  alias Server.Agenda
  alias Server.Jot
  alias Server.Proposal
  alias Server.Repo

  @kinds ["todo", "reminder", "note", "waiting", "project"]

  @doc "The export of the jots and piles `via` holds."
  @spec build(String.t()) :: map()
  def build(via) do
    things = Enum.map(jots(via), &thing/1)
    agendas = Enum.map(piles(via), &agenda/1)
    proposals = Enum.map(Proposal.open(), &proposal/1)

    %{
      v: 1,
      things: things,
      agendas: agendas,
      proposals: proposals,
      settings: %{
        telegram_list_at: Server.OperatorConfig.setting("home_list_at"),
        telegram_morning_at: Server.OperatorConfig.setting("home_morning_at"),
        telegram_chat: Server.OperatorConfig.setting("home_chat")
      },
      counts: counts(things, agendas, proposals)
    }
  end

  defp jots(via), do: Repo.all(from(j in Jot, where: j.via == ^via and j.kind in ^@kinds, order_by: j.id))

  defp piles(via), do: Repo.all(from(a in Agenda, where: a.via == ^via, order_by: a.id))

  defp counts(things, agendas, proposals) do
    things
    |> Enum.frequencies_by(& &1.kind)
    |> Map.merge(Enum.frequencies_by(agendas, & &1.kind))
    |> Map.put("proposals", length(proposals))
  end

  defp thing(jot) do
    %{
      id: jot.id,
      kind: jot.kind,
      text: jot.text,
      state: state(jot),
      since: iso(jot.received_at),
      due_at: iso(jot.due_at),
      every: jot.every,
      every_day: jot.every_day,
      told_at: iso(jot.nudged_at),
      nudges: jot.nudges,
      project_id: jot.project_id,
      who: jot.waiting_on,
      plan: jot.plan,
      done_at: iso(jot.done_at),
      dropped_at: iso(jot.dropped_at),
      hidden_until: iso(jot.hidden_until),
      agenda_id: jot.agenda_id
    }
  end

  defp state(%Jot{dropped_at: %DateTime{}}), do: "dropped"
  defp state(%Jot{done_at: %DateTime{}}), do: "done"
  defp state(%Jot{someday_at: %DateTime{}}), do: "someday"
  defp state(%Jot{}), do: "open"

  defp agenda(agenda) do
    %{
      id: agenda.id,
      kind: agenda.kind,
      name: agenda.name,
      birthday: agenda.birthday,
      every: agenda.every,
      every_day: agenda.every_day,
      next_at: iso(agenda.next_at),
      told_for: iso(agenda.told_for)
    }
  end

  defp proposal(p), do: %{id: p.id, source: p.source, text: p.text, why: p.why, url: p.url}

  defp iso(nil), do: nil
  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)
end
