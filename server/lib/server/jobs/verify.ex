defmodule Server.Jobs.Verify do
  @moduledoc """
  The deterministic verifier for a workline that has just entered `verify`: runs
  `scripts/workline-verify.sh` (the gates, each recorded as CHECKS evidence, advance on green) from
  tlon's checkout, independent of the builder by construction — on the branch rebased onto
  origin/main in a throwaway checkout, so a fix that reached main after the branch was cut counts. Enqueued by `Server.Workline` on the
  flip. Where it cannot run — no checkout beside this release, no `mise` on the service's PATH — it
  says so on the thread, with the command to run by hand, rather than leaving the stage parked in
  silence.
  """
  use Oban.Worker,
    queue: :verify,
    max_attempts: 1,
    unique: [period: 600, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  alias Server.Channel

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid, "slug" => slug}}) do
    script = Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")

    # the workline's own checkout: the script borrows its installed deps for the throwaway one
    tree = with %Server.Thread{} = t <- Channel.thread(tid), {:ok, path} <- Server.worktree_for_thread(t), do: path

    cond do
      !File.exists?(script) -> by_hand(tid, slug, "no tlon checkout at #{Server.Profiles.tlon_root()}")
      !System.find_executable("mise") -> by_hand(tid, slug, "no mise on the service's PATH")
      !is_binary(tree) -> by_hand(tid, slug, "no checkout of work/#{slug} (#{inspect(tree)})")
      true -> run(script, tid, slug, tree)
    end
  end

  defp run(script, tid, slug, tree) do
    case System.cmd("bash", [script, to_string(tid), slug, tree], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, "workline-verify exited #{code}: #{String.slice(out, -400, 400)}"}
    end
  end

  defp by_hand(tid, slug, why) do
    {:ok, _} =
      Channel.post(%{
        thread_id: tid,
        author: "tlon",
        body: "verify can't run here (#{why}) — run it by hand: mise run workline:verify -- #{tid} #{slug}"
      })

    :ok
  end
end
