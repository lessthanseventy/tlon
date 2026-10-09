defmodule Server.Recall.Recheck do
  @moduledoc """
  Recheck one fact that names code: probe each ref `Server.Recall.CodeRefs` finds against
  `origin/main` of the thread's project repos, and record `check_passed` (every ref found) or
  `check_failed` (one is gone), correlated `fact:<id>` so `Server.Recall.Strength` weighs it.
  Nothing is recorded for prose, a fact with no project repo, or a fact already rechecked in the
  last 24h. The server never runs the fact's own `check_cmd`.
  """
  import Ecto.Query

  alias Server.Dossier
  alias Server.Event
  alias Server.Fact
  alias Server.Recall.CodeRefs
  alias Server.Recall.Probe
  alias Server.Repo
  alias Server.Thread

  @prefix "server recheck: "
  @window_s 24 * 3600

  @spec run(Fact.t()) :: {:ok, :passed | :failed | :skipped}
  def run(%Fact{thread_id: nil}), do: {:ok, :skipped}

  def run(%Fact{} = fact) do
    with [_ | _] = refs <- CodeRefs.extract(fact.text),
         [_ | _] = repos <- repo_paths(fact.thread_id),
         false <- rechecked_recently?(fact) do
      missing = Enum.reject(refs, fn ref -> Enum.any?(repos, &Probe.found?(&1, ref)) end)
      record(fact, refs, missing)
    else
      _ -> {:ok, :skipped}
    end
  end

  defp record(fact, refs, missing) do
    {:ok, _} =
      Dossier.record_check(%{
        thread_id: fact.thread_id,
        exit: if(missing == [], do: 0, else: 1),
        cmd: @prefix <> summary(refs),
        tail: if(missing == [], do: nil, else: "gone: " <> summary(missing)),
        correlation: "fact:#{fact.id}"
      })

    {:ok, if(missing == [], do: :passed, else: :failed)}
  end

  defp summary(refs), do: Enum.map_join(refs, ", ", fn {_kind, name} -> name end)

  defp repo_paths(thread_id) do
    with %Thread{project_id: pid} when not is_nil(pid) <- Repo.get(Thread, thread_id),
         %Server.Project{repos: repos} <- Server.Projects.get(pid) do
      for %{"path" => path} <- repos || [], do: path
    else
      _ -> []
    end
  end

  # `detail` is a text column, hence the substring match
  # the ref set is a pure function of the text, so a repeat inside the window can only repeat the verdict
  defp rechecked_recently?(fact) do
    since = DateTime.add(DateTime.utc_now(), -@window_s, :second)

    Repo.exists?(
      from e in Event,
        where:
          e.correlation == ^"fact:#{fact.id}" and e.kind in ["check_passed", "check_failed"] and
            e.created_at > ^since and like(e.detail, ^("%" <> @prefix <> "%"))
    )
  end
end
