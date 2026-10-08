defmodule Server.Jobs.Land do
  @moduledoc """
  The merge queue: an approved workline's landing, one at a time (queue `landing`, concurrency 1).
  `Server.Workline.land_queued/2` rebases `work/<slug>` onto main and gates it there before main
  moves — so what lands is what was checked, on the main it lands on, never a verify against a main
  that has moved since. The gate is the full check (`scripts/workline-verify.sh` with
  `WORKLINE_GATE=1`: evidence recorded, nothing advanced, nothing posted).
  """
  use Oban.Worker,
    queue: :landing,
    max_attempts: 3,
    unique: [period: :infinity, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}, attempt: attempt, max_attempts: max}) do
    case Server.Repo.get(Server.Thread, tid) do
      nil ->
        :ok

      thread ->
        # a gate cut off (a restart) leaves the landing queued; this attempt fails so Oban runs it
        # again, and only the last one cut off bounces it
        case Server.Workline.land_queued(thread, last: attempt >= max) do
          {:error, {:interrupted, why}} -> {:error, why}
          _ -> :ok
        end
    end
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
