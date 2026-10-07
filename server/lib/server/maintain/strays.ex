defmodule Server.Maintain.Strays do
  @moduledoc """
  Worktrees no thread is working in: a project's `.worktrees/<name>` whose thread is closed, gone,
  or is its workspace's standing thread (the lobby never finishes, so work parked on it never
  surfaces otherwise). The Maintain sweep removes the ones holding nothing; the rest are the
  needs list's stranded work (`Server.Office.Needs`), never deleted by a sweep.
  """
  import Ecto.Query

  alias Server.Channel
  alias Server.Repo
  alias Server.Thread

  @doc "Every stray worktree: `%{repo, name, thread}`, `thread` nil when there is none."
  def worktrees do
    for repo <- repos(),
        name <- Server.Worktree.names(repo),
        thread = owner(name),
        stray?(thread),
        do: %{repo: repo, name: name, thread: thread}
  end

  defp repos do
    from(p in Server.Project)
    |> Repo.all()
    |> Enum.flat_map(fn p ->
      case Server.Projects.primary_repo_path(p) do
        {:ok, path} -> [path]
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  defp owner("t" <> id) do
    case Integer.parse(id) do
      {n, ""} -> Repo.get(Thread, n)
      _ -> Repo.get_by(Thread, slug: "t" <> id)
    end
  end

  defp owner(slug), do: Repo.get_by(Thread, slug: slug)

  defp stray?(nil), do: true
  defp stray?(%Thread{state: "closed"}), do: true
  defp stray?(thread), do: Channel.root_machine_thread?(thread)
end
