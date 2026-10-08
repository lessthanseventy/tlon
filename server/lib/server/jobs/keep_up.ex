defmodule Server.Jobs.KeepUp do
  @moduledoc """
  Every few minutes, each project repo's landings that GitHub left behind main are rebased so their
  auto-merge can go (`Server.Workline.Publish.refresh_behind/2`), and its main checkout is brought
  level with origin/main, fast-forward only (`follow_main/2`); one that has drifted is a note for
  the operator, never a merge.
  """
  use Oban.Worker, queue: :default, max_attempts: 1, unique: [period: 120]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    for repo <- repos() do
      Server.Workline.Publish.refresh_behind(repo)
      drifted(repo, Server.Workline.Publish.follow_main(repo))
    end

    :ok
  end

  defp drifted(repo, {:diverged, n}) do
    text =
      "#{repo}: local main has #{n} commit(s) origin/main doesn't — move them to a branch, then reset main to origin/main"

    if !Enum.any?(Server.Rollout.pending(), &(&1.text == text)), do: GenServer.cast(Server.Rollout, {:note, text})
  end

  defp drifted(_repo, _result), do: :ok

  defp repos do
    Server.Project
    |> Server.Repo.all()
    |> Enum.flat_map(fn p ->
      case Server.Projects.primary_repo_path(p) do
        {:ok, path} -> [path]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end
end
