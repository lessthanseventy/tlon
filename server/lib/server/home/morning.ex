defmodule Server.Home.Morning do
  @moduledoc """
  The morning message, said once a day at `home_morning_at` (`Server.Home.Inbox.morning/6`): today's
  meetings (`Server.Home.Day.meetings/1`), the one thing to start with (`Server.Home.now/3`), the
  agendas whose time is today and have a pile, what sources proposed (`Server.Home.Proposals`, with an
  Add and a No under each in the chat) and the waiting-ons a source has since settled. Nothing when
  there is nothing to say.
  """

  alias Server.Agenda
  alias Server.Home
  alias Server.Home.Clock
  alias Server.Home.Day
  alias Server.Home.Proposals
  alias Server.Jot
  alias Server.Proposal

  @doc """
  The message for `via` at `now`: `{text, opts, settled}`, `opts` the `say` options (the proposals'
  buttons) and `settled` the settled rows the text says, to be recorded once it went out. nil when
  there is nothing to say. `meetings` are `Server.Home.Day` rows, read from the calendar when nil.
  """
  @spec compose(String.t(), DateTime.t(), [Day.meeting()] | nil) :: {String.t(), keyword(), [Proposal.t()]} | nil
  def compose(via, now, meetings \\ nil),
    do: build(via, now, meetings, Proposal.settled(), Proposals.say(Proposal.open()) || {nil, []})

  @doc """
  The message as plain text, for a surface with no buttons (the desktop's alert): `{text, settled}`,
  `settled` the rows it says. A read records nothing: the inbox's tick does (`Server.Home.Inbox.morning/6`),
  when it says the message in the chat or, with no chat, at the slot. Rows told since `since` are said
  again, so the alert reads the same all the while it is up. nil when there is nothing to say.
  """
  @spec plain(String.t(), DateTime.t(), DateTime.t(), [Day.meeting()] | nil) :: {String.t(), [Proposal.t()]} | nil
  def plain(via, now, since, meetings \\ nil) do
    settled = Proposal.settled(since)

    with {text, _opts, settled} <-
           build(via, now, meetings, settled, {Proposals.plain(Proposal.open()), []}),
         do: {text, settled}
  end

  defp build(via, now, meetings, settled, {proposed, opts}) do
    sections = [
      meetings(meetings || Day.meetings(now)),
      start(now),
      agendas(via, now),
      Proposals.settled(settled),
      proposed
    ]

    case Enum.reject(sections, &is_nil/1) do
      [] -> nil
      parts -> {Enum.join(["Good morning." | parts], "\n\n"), opts, settled}
    end
  end

  defp meetings(meetings) do
    case Enum.filter(meetings, &(&1.day == "today")) do
      [] -> nil
      today -> Enum.join(["Today:" | Enum.map(today, &meeting/1)], "\n")
    end
  end

  defp meeting(m), do: "• #{when_said(m)} #{m.title}#{if m.tentative, do: " (tentative)"}"

  defp when_said(%{all_day: true}), do: "all day"
  defp when_said(m), do: clock(m.starts_at)

  defp clock(at), do: at |> Clock.local() |> Calendar.strftime("%H:%M")

  defp start(now) do
    case Home.now([], nil, now) do
      %{pick: nil} -> nil
      %{say: say} -> "Start with: #{say}"
    end
  end

  defp agendas(via, now) do
    today = now |> Clock.local() |> NaiveDateTime.to_date()

    lines =
      for %Agenda{next_at: %DateTime{} = at} = agenda <- Agenda.all(via),
          NaiveDateTime.to_date(Clock.local(at)) == today,
          [_ | _] = notes <- [Jot.agenda_notes(agenda.id)],
          do: "• #{agenda.name} at #{clock(at)}: #{length(notes)} #{if length(notes) == 1, do: "thing", else: "things"}"

    if lines != [], do: Enum.join(["Due today:" | lines], "\n")
  end
end
