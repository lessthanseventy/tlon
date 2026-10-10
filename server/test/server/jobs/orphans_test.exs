defmodule Server.Jobs.OrphansTest do
  # At boot, what this node left executing goes back in its queue; another node's is left alone.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Jobs.Orphans

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    :ok
  end

  defp executing(node) do
    {:ok, job} = %{thread_id: System.unique_integer([:positive])} |> Server.Jobs.Land.new() |> Oban.insert()

    Server.Repo.update_all(from(j in Oban.Job, where: j.id == ^job.id),
      set: [state: "executing", attempted_by: [node, "landing"], attempted_at: DateTime.utc_now()]
    )

    job.id
  end

  test "this node's executing jobs are requeued at boot; another node's keep running" do
    mine = executing("funes@here")
    theirs = executing("other@there")

    assert Orphans.requeue("funes@here") == 1
    assert %{state: "available"} = Server.Repo.get!(Oban.Job, mine)
    assert %{state: "executing"} = Server.Repo.get!(Oban.Job, theirs)
  end
end
