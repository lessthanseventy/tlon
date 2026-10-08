defmodule Server.Release.Candidate do
  @moduledoc """
  Whether a commit on main is releasable (pm-and-release design §4): the mechanical checks, each
  passing or failing with why, for the PM to read rather than redo.

    * `gate` — the newest finished `check:main` run recorded on exactly this commit passed;
    * `smoke` — the same for `release:smoke`;
    * `quiet` — nothing is mid-flight (`Server.Rollout.busy/0`).

  A run names its commit itself (`ran-on: <check> <sha>`, `Server.ScheduleRun`), so a nightly that
  ran on another commit is no evidence for this one. §4's check 3, a track half-shipped where you'd
  see it, is the PM's judgment and not here.
  """

  import Ecto.Query

  alias Server.Repo
  alias Server.ScheduleRun

  @type result :: %{check: :gate | :smoke | :quiet, ok: boolean(), why: String.t()}

  @doc "Each check on `sha` (a full commit id). `busy:` stands in for `Server.Rollout.busy/0`."
  @spec check(String.t(), keyword()) :: [result()]
  def check(sha, opts \\ []) do
    busy = Keyword.get(opts, :busy, &Server.Rollout.busy/0)
    [ran(:gate, "check:main", sha), ran(:smoke, "release:smoke", sha), quiet(busy.())]
  end

  @doc "Whether every check on `sha` passes."
  @spec releasable?(String.t(), keyword()) :: boolean()
  def releasable?(sha, opts \\ []), do: Enum.all?(check(sha, opts), & &1.ok)

  @doc "The checks as lines to print, the verdict last (`release:status`)."
  @spec lines(String.t(), keyword()) :: [String.t()]
  def lines(sha, opts \\ []) do
    results = check(sha, opts)

    Enum.map(results, &"#{String.pad_trailing(to_string(&1.check), 6)}#{if &1.ok, do: "✓", else: "✗"} #{&1.why}") ++
      ["releasable: #{if Enum.all?(results, & &1.ok), do: "yes", else: "no"}"]
  end

  defp ran(check, task, sha) do
    name = to_string(check)

    case newest(where(ScheduleRun, [r], r.check_name == ^name and r.sha == ^sha)) do
      %{status: "ok"} = r ->
        %{check: check, ok: true, why: "#{task} passed on #{short(sha)} (run ##{r.id}, #{r.finished_at})"}

      %{status: status} = r ->
        %{check: check, ok: false, why: "#{task} #{status} on #{short(sha)} (run ##{r.id})"}

      nil ->
        %{check: check, ok: false, why: "no #{task} on #{short(sha)}#{elsewhere(name)}"}
    end
  end

  defp elsewhere(name) do
    case newest(where(ScheduleRun, [r], r.check_name == ^name)) do
      nil -> ""
      r -> "; its last run was on #{short(r.sha)}"
    end
  end

  defp newest(q),
    do: Repo.one(from r in q, where: not is_nil(r.finished_at), order_by: [desc: r.finished_at, desc: r.id], limit: 1)

  defp quiet([]), do: %{check: :quiet, ok: true, why: "nothing mid-flight"}
  defp quiet(busy), do: %{check: :quiet, ok: false, why: Enum.join(busy, "; ")}

  defp short(sha), do: String.slice(sha, 0, 7)
end
