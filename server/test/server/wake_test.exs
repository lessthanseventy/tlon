defmodule Server.WakeTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Wake

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "a pane that never drains"})
    %{thread: thread}
  end

  test "a wake its pane never took is reported and let go; a fresh one waits", %{thread: t} do
    {:ok, old} = Wake.queue(t.id, "hronir", "ping")
    old_at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
    Repo.update_all(from(w in Wake, where: w.id == ^old.id), set: [inserted_at: old_at])
    {:ok, _fresh} = Wake.queue(t.id, "hronir", "pong")

    assert Wake.report_overdue() == 1
    assert Wake.take(t.id, "hronir") == ["pong"]
  end

  test "a wake whose pane is mid-turn (a long tool call) is not overdue; one past the stale-turn clock is",
       %{thread: t} do
    {:ok, a} = Server.Staff.register_agent(%{name: "nolan", mandate: "m", engine: "e"})
    {:ok, _} = Server.Staff.start_session(%{agent_id: a.id, thread_id: t.id})
    :ok = Server.Staff.mark_thinking(t.id, "nolan", DateTime.truncate(DateTime.utc_now(), :second))
    {:ok, old} = Wake.queue(t.id, "nolan", "ping")
    old_at = DateTime.utc_now() |> DateTime.add(-600) |> DateTime.truncate(:second)
    Repo.update_all(from(w in Wake, where: w.id == ^old.id), set: [inserted_at: old_at])

    assert Wake.report_overdue() == 0

    stale = DateTime.add(old_at, -Server.Presence.Thinking.stale_turn_seconds())
    :ok = Server.Staff.mark_thinking(t.id, "nolan", stale)
    assert Wake.report_overdue() == 1
    assert Wake.take(t.id, "nolan") == []
  end
end
