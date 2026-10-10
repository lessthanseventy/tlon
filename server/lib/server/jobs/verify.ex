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
    max_attempts: 3,
    unique: [period: 600, keys: [:thread_id], states: [:available, :scheduled, :executing]]

  import Ecto.Query

  alias Server.Channel

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid, "slug" => slug}} = job) do
    script = Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")

    # the workline's own checkout: the script borrows its installed deps for the throwaway one
    thread = Channel.thread(tid)
    tree = with %Server.Thread{} = t <- thread, {:ok, path} <- Server.worktree_for_thread(t), do: path

    cond do
      match?(%Server.Thread{state: "closed"}, thread) -> {:cancel, "thread ##{tid} is closed"}
      !File.exists?(script) -> by_hand(tid, slug, "no tlon checkout at #{Server.Profiles.tlon_root()}")
      !System.find_executable("mise") -> by_hand(tid, slug, "no mise on the service's PATH")
      !is_binary(tree) -> by_hand(tid, slug, "no checkout of work/#{slug} (#{inspect(tree)})")
      true -> run(script, tid, slug, tree, job)
    end
  end

  defp run(script, tid, slug, tree, job) do
    since = last_verify_id(slug)
    result = System.cmd("bash", [script, to_string(tid), slug, tree], stderr_to_stdout: true)
    finish(tid, slug, since, result, job)
  end

  @doc """
  How a run ends: one that recorded a result since `since` — green or red — is done, red going to
  the sheriff. One that recorded nothing was cut off (a service restart, a signal) or could not
  start, and is an error so Oban runs it again (`max_attempts` 3); only the last attempt tells the
  sheriff it could not run. A thread closed meanwhile is nobody's work: the job is cancelled, not retried.
  """
  def finish(tid, slug, since, {out, _code}, %{attempt: attempt, max_attempts: max}) do
    case {last_verify(slug), Channel.thread(tid)} do
      {%{id: id} = e, t} when id > since ->
        if e.kind == "check_failed" and t,
          do:
            Server.Sheriff.report(
              t,
              "verify is red: #{e.detail["cmd"]} (exit #{e.detail["exit"]}) — #{tail(e.detail["tail"])}"
            )

        :ok

      {_, %Server.Thread{state: "closed"}} ->
        {:cancel, "thread ##{tid} is closed"}

      {_, t} ->
        if attempt >= max and t, do: Server.Sheriff.report(t, "verify could not run: #{tail(out)}")
        {:error, "verify recorded nothing (attempt #{attempt}/#{max}): #{tail(out)}"}
    end
  end

  defp last_verify_id(slug), do: (last_verify(slug) || %{id: 0}).id

  defp last_verify(slug) do
    Server.Repo.one(
      from e in Server.Event,
        where: e.correlation == ^"workline:#{slug}:verify" and e.kind in ["check_passed", "check_failed"],
        order_by: [desc: e.id],
        limit: 1
    )
  end

  defp tail(text), do: text |> to_string() |> String.trim() |> String.slice(-2000, 2000)

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
