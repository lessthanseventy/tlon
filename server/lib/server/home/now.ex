defmodule Server.Home.Now do
  @moduledoc """
  What to do now: one open thing out of the lot, and a few words on why. A pure choice over the open
  reminders and to-dos at a moment, so it is the same twice. Overdue reminders come first, the
  most overdue first. Then the to-dos: each scores its age in days (at most 30), five more for the
  next step of a project, and, when the operator says how many minutes they have, a bonus for the
  biggest size that still fits (a to-do's `mins`, 10 when unsized); one that does not fit is chosen
  only when nothing fits. Never chosen: a reminder still to come, a thing someone put off or
  dropped, one the operator said "not today" to, one in `skip`.
  """

  alias Server.Jot

  @default_mins 10

  @doc """
  The thing to do at `now` out of `things`, with why: `{:ok, jot, why}`, `:none` when nothing is
  left. Options: `skip` (ids to leave out), `minutes` (the time the operator has) and `projects`
  (project id => its text, to name a step's project).
  """
  @spec pick([Jot.t()], DateTime.t(), keyword()) :: {:ok, Jot.t(), String.t()} | :none
  def pick(things, now, opts \\ []) do
    skip = Keyword.get(opts, :skip, [])
    minutes = Keyword.get(opts, :minutes)
    projects = Keyword.get(opts, :projects, %{})
    live = Enum.filter(things, &candidate?(&1, now, skip))
    {overdue, todos} = Enum.split_with(live, &match?(%Jot{kind: "reminder", due_at: %DateTime{}}, &1))

    case {Enum.sort_by(overdue, &{DateTime.to_unix(&1.due_at), &1.id}), todos} do
      {[jot | _], _} -> {:ok, jot, "due " <> ago(DateTime.diff(now, jot.due_at))}
      {[], []} -> :none
      {[], todos} -> todo(todos, now, minutes, projects)
    end
  end

  defp candidate?(%Jot{} = jot, now, skip) do
    jot.id not in skip and jot.kind in ["reminder", "todo"] and is_nil(jot.done_at) and is_nil(jot.dropped_at) and
      is_nil(jot.someday_at) and not hidden?(jot, now) and not coming?(jot, now)
  end

  defp hidden?(%Jot{hidden_until: nil}, _now), do: false
  defp hidden?(%Jot{hidden_until: until}, now), do: DateTime.after?(until, now)

  defp coming?(%Jot{kind: "reminder", due_at: %DateTime{} = due}, now), do: DateTime.after?(due, now)
  defp coming?(_jot, _now), do: false

  defp todo(todos, now, minutes, projects) do
    {fits, bigger} = Enum.split_with(todos, &fits?(&1, minutes))

    case fits do
      [] -> bigger |> best(now, nil) |> then(&{:ok, &1, "longer than #{minutes} minutes, but it is what is open"})
      fits -> fits |> best(now, minutes) |> then(&{:ok, &1, why(&1, now, minutes, projects)})
    end
  end

  defp best(todos, now, minutes), do: Enum.min_by(todos, &{-score(&1, now, minutes), &1.id})

  defp score(jot, now, minutes) do
    age = jot |> age(now) |> min(30)
    step = if jot.project_id, do: 5, else: 0
    fit = if minutes, do: 5 * size(jot) / minutes, else: 0
    age + step + fit
  end

  defp fits?(_jot, nil), do: true
  defp fits?(jot, minutes), do: size(jot) <= minutes

  defp size(%Jot{mins: nil}), do: @default_mins
  defp size(%Jot{mins: mins}), do: mins

  defp age(jot, now), do: div(DateTime.diff(now, jot.received_at), 86_400)

  defp why(%Jot{project_id: id} = jot, now, minutes, projects) do
    case {Map.fetch(projects, id), age(jot, now), minutes} do
      {{:ok, name}, _age, _minutes} -> "next step of #{name}"
      {_none, age, _minutes} when age >= 3 -> "sat #{age} days"
      {_none, _age, minutes} when is_integer(minutes) -> "fits #{minutes} minutes"
      _ -> "next on the list"
    end
  end

  defp ago(s) when s < 60, do: "just now"
  defp ago(s) when s < 3600, do: "#{div(s, 60)} minutes ago"
  defp ago(s) when s < 7200, do: "an hour ago"
  defp ago(s) when s < 86_400, do: "#{div(s, 3600)} hours ago"
  defp ago(s) when s < 172_800, do: "a day ago"
  defp ago(s), do: "#{div(s, 86_400)} days ago"
end
