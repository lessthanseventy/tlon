defmodule Server.Jobs.Land do
  @moduledoc """
  The merge queue: an approved workline's landing, a landed one's GitHub isn't merging put back in
  it (args `%{"thread_id", "reland" => true}`, `Server.Workline.reland_queued/2`), or a reviewed
  PR's (`Server.PRLanding`, args `%{"pr", "branch", "on_thread"}`), one at a time (queue `landing`,
  concurrency 1).
  `Server.Workline.land_queued/2` rebases `work/<slug>` onto origin's main and gates it there — so
  what lands is what was checked, on the main it lands on, never a verify against a main that has
  moved since. The gate is the full check (`scripts/workline-verify.sh` with
  `WORKLINE_GATE=1`: evidence recorded, nothing advanced, nothing posted).
  """
  use Oban.Worker,
    queue: :landing,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:thread_id, :branch], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"pr" => _} = args, attempt: attempt, max_attempts: max}) do
    case Server.PRLanding.land(args, last: attempt >= max) do
      {:error, {:interrupted, why}} when attempt < max -> {:error, why}
      _ -> :ok
    end
  end

  def perform(%Oban.Job{args: %{"thread_id" => tid} = args, attempt: attempt, max_attempts: max}) do
    # the lock only orders this read against a send-back (which moves the row under it): one in
    # flight is seen; it doesn't guard the landing, which send-back refuses once this job exists
    {:ok, thread} =
      Server.Repo.transaction(fn ->
        Server.Repo.one(from t in Server.Thread, where: t.id == ^tid, lock: "FOR UPDATE")
      end)

    queued = if args["reland"], do: &Server.Workline.reland_queued/2, else: &Server.Workline.land_queued/2
    if thread, do: land(thread, queued, attempt, max), else: :ok
  end

  @doc """
  Run a landing attempt. One that raises on the last attempt is about to be discarded, leaving the
  workline at review with nothing queued, so the sheriff is told before it raises on to Oban.
  """
  def reported(thread, attempt, max, land) do
    land.()
  rescue
    e ->
      if attempt >= max,
        do:
          Server.Sheriff.report(
            thread,
            "the merge queue's landing of work/#{thread.slug} crashed on its last attempt, so nothing landed and it waits at review with nothing queued: #{Exception.message(e)}"
          )

      reraise e, __STACKTRACE__
  end

  @doc "The landing's gate: the full check on the rebased branch, in the workline's own repo."
  def gate(thread, _repo, _branch) do
    script = Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")

    case Server.worktree_for_thread(thread) do
      {:ok, tree} ->
        "bash"
        |> System.cmd([script, to_string(thread.id), thread.slug, tree],
          env: [{"WORKLINE_GATE", "1"}],
          stderr_to_stdout: true
        )
        |> gate_result()

      {:error, why} ->
        {:error, "there is no checkout of it to gate (#{inspect(why)})."}
    end
  end

  @doc """
  A PR's landing gate: the same full check, by the same script in its branch mode (`LAND_REF`, the
  rebased ref; no thread, so no evidence recorded), named on the checks rack as the PR.
  """
  def gate_pr(pr, branch, repo, ref) do
    script = Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")
    slug = "pr-#{pr}-" <> String.replace(branch, ~r/[^A-Za-z0-9-]/, "-")

    "bash"
    |> System.cmd([script, "-", slug, repo],
      env: [{"WORKLINE_GATE", "1"}, {"LAND_REF", ref}, {"CHECKS_LABEL", "PR ##{pr} landing #{branch}"}],
      stderr_to_stdout: true
    )
    |> gate_result()
  end

  @doc """
  The gate's run → its verdict: exit 0 green; killed by a signal (128 + n — a service restart's
  SIGTERM is 143) is `{:interrupted, why}`, a gate that never finished, not a red; anything else red.
  """
  def gate_result({_out, 0}), do: {:ok, :green}

  def gate_result({_out, code}) when code > 128,
    do: {:error, {:interrupted, "the gate was cut off before it finished (killed, exit #{code})"}}

  def gate_result({out, code}),
    do:
      {:error,
       "the full check on main with this branch is red (exit #{code}): #{String.slice(String.trim(out), -2000, 2000)}"}

  # a gate cut off (a restart) leaves the landing queued; this attempt fails so Oban runs it again,
  # and only the last one cut off bounces it
  defp land(thread, queued, attempt, max) do
    case reported(thread, attempt, max, fn -> queued.(thread, last: attempt >= max) end) do
      {:error, {:interrupted, why}} -> {:error, why}
      _ -> :ok
    end
  end
end
