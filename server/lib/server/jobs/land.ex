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
    max_attempts: 1,
    unique: [period: :infinity, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid}}) do
    case Server.Repo.get(Server.Thread, tid) do
      nil ->
        :ok

      thread ->
        Server.Workline.land_queued(thread)
        :ok
    end
  end

  @doc "The landing's gate: the full check on the rebased branch, in the workline's own repo."
  def gate(thread, _repo, _branch) do
    script = Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")

    with {:ok, tree} <- Server.worktree_for_thread(thread),
         {_, 0} <-
           System.cmd("bash", [script, to_string(thread.id), thread.slug, tree],
             env: [{"WORKLINE_GATE", "1"}],
             stderr_to_stdout: true
           ) do
      {:ok, :green}
    else
      {:error, why} ->
        {:error, "there is no checkout of it to gate (#{inspect(why)})."}

      {out, code} ->
        {:error,
         "the full check on main with this branch is red (exit #{code}): #{String.slice(String.trim(out), -2000, 2000)}"}
    end
  end
end
