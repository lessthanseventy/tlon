defmodule Server.Workline.Artifacts do
  @moduledoc """
  The owed-artifact checker seam: is the stage's exit evidence really there? Requirements:
  `{:file, name}` (committed under `work/<slug>/`), `:branch` (the workline branch exists),
  `:checks` (verify-stage evidence — a `check_passed` correlated `workline:<slug>:verify`).
  A behaviour so the stage machine tests with stubs and the git impl stays one module.
  """

  @callback check(Server.Thread.t(), {:file, String.t()} | :branch | :checks) ::
              {:ok, String.t()} | {:error, String.t()}
end

defmodule Server.Workline.Artifacts.Git do
  @moduledoc """
  The real checker: files must be COMMITTED (git ls-files, not mere existence — an untracked
  intent.md is not an artifact), the branch is `work/<slug>`, verify evidence is a
  `check_passed` event correlated `workline:<slug>:verify`. Git runs in the thread's own repo
  (`root/1`), so a workline on another project is checked against that project.
  """

  @behaviour Server.Workline.Artifacts

  import Ecto.Query

  alias Server.Event
  alias Server.Repo

  @impl true
  def check(thread, {:file, name}) do
    rel = Path.join(["work", thread.slug, name])

    case git(thread, ["ls-files", "--error-unmatch", rel]) do
      {_out, 0} -> {:ok, "committed #{rel}"}
      {_out, _} -> sane_root_or(thread, fn -> {:error, "#{rel} is not committed"} end)
    end
  end

  def check(thread, :branch) do
    branch = "work/#{thread.slug}"

    case git(thread, ["rev-parse", "--verify", "--quiet", branch]) do
      {sha, 0} -> {:ok, "#{branch} @ #{String.slice(String.trim(sha), 0, 12)}"}
      {_out, _} -> sane_root_or(thread, fn -> {:error, "branch #{branch} does not exist"} end)
    end
  end

  def check(thread, :checks) do
    correlation = "workline:#{thread.slug}:verify"

    passed =
      Repo.exists?(
        from e in Event,
          where: e.thread_id == ^thread.id and e.kind == "check_passed" and e.correlation == ^correlation
      )

    if passed,
      do: {:ok, "verify evidence recorded (#{correlation})"},
      else: {:error, "no check_passed correlated #{correlation}"}
  end

  defp git(thread, args), do: System.cmd("git", ["-C", root(thread) | args], stderr_to_stdout: true)

  # A failed check on a broken root would otherwise read as "not committed" — an actionable-
  # sounding but FALSE diagnosis that wedges every workline. Distinguish the environment fault.
  defp sane_root_or(thread, not_committed) do
    case git(thread, ["rev-parse", "--git-dir"]) do
      {_out, 0} -> not_committed.()
      {_out, _} -> {:error, "workline root #{root(thread)} is not a git worktree — set TLON_WORKLINE_ROOT"}
    end
  end

  @doc """
  The fallback git root for a thread with no project: `config :server, :workline_root`, else cwd.
  """
  def root, do: Application.get_env(:server, :workline_root) || File.cwd!()

  @doc """
  The git root a thread's artifacts live in: `Server.repo_for_thread/1` (its project's repo, else its workspace's), else `root/0`. Shared with `Scribe` so both sides act on one tree.
  """
  def root(thread) do
    case Server.repo_for_thread(thread) do
      {:ok, repo} -> repo
      {:error, _} -> root()
    end
  end
end
