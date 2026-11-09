defmodule Server.HeldReviewTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.{HeldReview, Tickets}

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Held"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "beatriz", archetype: "pm"})
    {:ok, _} = Server.Channel.open_thread(%{title: "lobby", scope: "machine", workspace_id: ws.id})
    %{ws: ws}
  end

  defp held(ws, title, age_days, labels \\ ["held"]) do
    {:ok, t} = Tickets.file(%{workspace_id: ws.id, title: title, labels: labels})

    Server.Repo.update_all(from(x in Server.Ticket, where: x.id == ^t.id),
      set: [updated_at: DateTime.add(DateTime.utc_now(), -age_days, :day)]
    )

    t
  end

  defp posts(ws) do
    root = Server.Channel.machine_thread(ws.id)
    Enum.filter(Server.Channel.thread_messages(root), &(&1.body =~ "Held for 30"))
  end

  test "the review is on the Monday crontab" do
    crontab =
      Enum.find_value(Application.get_env(:server, Oban)[:plugins], fn
        {Oban.Plugins.Cron, o} -> o[:crontab]
        _ -> nil
      end)

    assert {"0 7 * * 1", Server.Jobs.HeldReview} in crontab
  end

  test "lists the held tickets over 30 days, not the newer, unheld or done ones", %{ws: ws} do
    a = held(ws, "waits on upstream", 45)
    b = held(ws, "waits on a vendor", 31)
    new = held(ws, "waits a little", 5)
    unheld = held(ws, "not held at all", 60, [])

    assert HeldReview.run() == 1
    [m] = posts(ws)
    assert m.body =~ "##{a.id} waits on upstream, held 45 days"
    assert m.body =~ "##{b.id} waits on a vendor"
    refute m.body =~ "##{new.id} "
    refute m.body =~ "##{unheld.id} "
    assert m.body =~ "Keep" and m.body =~ "Close" and m.body =~ "Unhold"
    assert m.kind == "notice"
  end

  test "no stale held ticket, no post", %{ws: ws} do
    held(ws, "recent", 3)
    assert HeldReview.run() == 0
    assert posts(ws) == []
  end
end
