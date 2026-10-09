defmodule Server.Jobs.LandCrashTest do
  # A landing that crashes on its last attempt is discarded by Oban, and the workline would sit at
  # review with nothing queued, so the sheriff is told first; an earlier crash is the retry's.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Jobs.Land
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    roster = [%{"archetype" => "builder", "name" => "emma"}, %{"archetype" => "sheriff", "name" => "scharlach"}]
    {:ok, ws} = Server.Workspaces.register(%{name: "Crash", roster: roster})
    {:ok, t} = Server.Workline.open(%{title: "t crash", slug: "crash", stage: "review", workspace_id: ws.id})
    %{thread: t}
  end

  defp told(thread),
    do:
      Repo.all(from m in Server.Message, where: m.thread_id != ^thread.id and like(m.body, "%crashed%"), select: m.body)

  defp crash, do: raise(MatchError, term: {"", 128})

  test "a crash on the last attempt reaches the sheriff, then raises for Oban", %{thread: t} do
    assert_raise MatchError, fn -> Land.reported(t, 3, 3, &crash/0) end
    assert [report] = told(t)
    assert report =~ "work/crash"
  end

  test "an earlier attempt's crash is left to the retry, told to no one", %{thread: t} do
    assert_raise MatchError, fn -> Land.reported(t, 1, 3, &crash/0) end
    assert told(t) == []
  end

  test "a landing that doesn't crash is its own result", %{thread: t} do
    assert {:ok, :landed} = Land.reported(t, 3, 3, fn -> {:ok, :landed} end)
  end
end
