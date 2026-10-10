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
end
