defmodule Server.Jobs.Verify do
  @moduledoc """
  The deterministic verifier for a workline that has just entered `verify`: runs
  `scripts/workline-verify.sh` (the gates, each recorded as CHECKS evidence, advance on green) from
  tlon's checkout, independent of the builder by construction. Enqueued by `Server.Workline` on the
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

    cond do
      !File.exists?(script) -> by_hand(tid, slug, "no tlon checkout at #{Server.Profiles.tlon_root()}")
      !System.find_executable("mise") -> by_hand(tid, slug, "no mise on the service's PATH")
      true -> run(script, tid, slug)
    end
  end

  defp run(script, tid, slug) do
    case System.cmd("bash", [script, to_string(tid), slug], stderr_to_stdout: true) do
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
