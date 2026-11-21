defmodule Server.Smoke do
  @moduledoc """
  The smoke of main's tip after a landing, run by the service (`Server.Jobs.Smoke`):
  `scripts/release-smoke.sh` builds the commit as a scratch release on its own port and db, and
  keeps its own one-smoke-per-commit lock.
  """
  import Ecto.Query

  alias Server.Jobs.Smoke, as: Job

  @doc """
  Queue the smoke of main's new tip `sha` after a landing: its run records `ran-on: smoke`,
  what `Server.Release.Candidate` reads, so a merge is smoked when it lands, not at night. One at a
  time: a newer tip's replaces one still queued; a build already running finishes.
  """
  @spec queue_candidate(String.t()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def queue_candidate(sha) do
    Oban.cancel_all_jobs(
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Smoke" and j.state in ["available", "scheduled"] and
            fragment("?->>'candidate' = 'true'", j.args)
    )

    Oban.insert(Job.new(%{ref: sha, sha: sha, candidate: true}))
  end

  @doc "The script that builds and runs the smoke (`config :server, :smoke_script` in tests)."
  @spec script() :: String.t()
  def script do
    Application.get_env(:server, :smoke_script) || script_in_main_root()
  end

  defp script_in_main_root do
    {:ok, root} = Server.Profiles.main_root()
    Path.join(root, "scripts/release-smoke.sh")
  end
end
