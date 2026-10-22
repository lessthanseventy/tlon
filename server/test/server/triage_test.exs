defmodule Server.TriageTest do
  # The PM's triage: when due, the server posts the backlog's changes to the workspace's PM on its
  # own thread (Server.Triage); the PM acts with the ticket tools.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Tickets
  alias Server.Triage

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.create(%{name: "Triage"})
    %{ws: ws}
  end

  defp file(ws, title, attrs \\ %{}), do: elem(Tickets.file(Map.merge(%{workspace_id: ws.id, title: title}, attrs)), 1)

  defp briefs(ws),
    do:
      for(
        t <- Server.Repo.all(from t in Server.Thread, where: t.workspace_id == ^ws.id and t.title == ^Triage.title()),
        m <- Server.Channel.thread_messages(t),
        m.body =~ "🗂 triage",
        do: m
      )

  test "the triage is on the hourly crontab" do
    crontab =
      Enum.find_value(Application.get_env(:server, Oban)[:plugins], fn
        {Oban.Plugins.Cron, o} -> o[:crontab]
        _ -> nil
      end)

    assert {"5 * * * *", Server.Jobs.Triage} in crontab
  end

  test "no PM on the bench, no triage", %{ws: ws} do
    file(ws, "a")
    assert Triage.run() == 0
    assert briefs(ws) == []
  end

  test "the first run briefs the PM on its own thread: new, loose, stale and look-alikes", %{ws: ws} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "beatriz", archetype: "pm"})
    epic = file(ws, "Toy", %{kind: "epic"})
    filed = file(ws, "The hall forgets the hire's face", %{epic_id: epic.id})
    loose = file(ws, "The rack reads all green while a line is red")
    twin = file(ws, "The rack reads all green while one line is red", %{})
    old = file(ws, "An old idea nobody touched")

    Server.Repo.update_all(from(t in Server.Ticket, where: t.id == ^old.id),
      set: [updated_at: DateTime.add(DateTime.utc_now(), -20, :day)]
    )

    assert Triage.run() == 1
    [m] = briefs(ws)
    thread = Server.Channel.thread(m.thread_id)
    assert Server.Channel.thread_lead(thread.id) == "beatriz"
    assert m.body =~ "@beatriz"
    assert m.body =~ "##{filed.id}"
    [_, loose_part] = String.split(m.body, "Loose", parts: 2)
    assert loose_part =~ "##{loose.id}"
    refute loose_part |> String.split("Stale") |> hd() =~ "##{filed.id}"
    assert m.body =~ ~r/Stale.*##{old.id}/s
    assert m.body =~ ~r/Look alike.*##{loose.id}.*##{twin.id}/s
  end

  test "due once a day, or sooner when five tickets have come in since", %{ws: ws} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "beatriz", archetype: "pm"})
    file(ws, "first")
    assert Triage.run() == 1
    file(ws, "one more")
    assert Triage.run() == 0
    for i <- 1..5, do: file(ws, "new #{i}")
    assert Triage.run() == 1
    assert Triage.run(DateTime.add(DateTime.utc_now(), 21, :hour)) == 1
    assert length(briefs(ws)) == 3
  end
end
