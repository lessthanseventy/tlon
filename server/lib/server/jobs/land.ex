defmodule Server.Jobs.Land do
  @moduledoc """
  The merge queue: an approved workline's landing, one at a time (queue `landing`, concurrency 1).
  `Server.Workline.land_queued/2` rebases `work/<slug>` onto origin's main and gates it there — so
  what lands is what was checked, on the main it lands on, never a verify against a main that has
  moved since. The gate is the full check (`scripts/workline-verify.sh` with
  `WORKLINE_GATE=1`: evidence recorded, nothing advanced, nothing posted).
  """
  use Oban.Worker,
    queue: :landing,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}, attempt: attempt, max_attempts: max}) do
    # the lock only orders this read against a send-back (which moves the row under it): one in
    # flight is seen; it doesn't guard the landing, which send-back refuses once this job exists
    {:ok, thread} =
      Server.Repo.transaction(fn ->
        Server.Repo.one(from t in Server.Thread, where: t.id == ^tid, lock: "FOR UPDATE")
      end)

    case thread do
      nil ->
        :ok

      thread ->
        # a gate cut off (a restart) leaves the landing queued; this attempt fails so Oban runs it
        # again, and only the last one cut off bounces it
        case reported(thread, attempt, max, fn -> Server.Workline.land_queued(thread, last: attempt >= max) end) do
          {:error, {:interrupted, why}} -> {:error, why}
          _ -> :ok
        end
    end
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
end
