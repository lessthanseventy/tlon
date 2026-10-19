defmodule Server.Jobs.Smoke do
  @moduledoc """
  Runs `scripts/release-smoke.sh` with `TLON_SMOKE_HOLD=1` for a QA seat, from the service (a
  seat's Bash can't: `Server.Smoke`). The job is the hold: it lives as long as the script does, until
  `stop_smoke` or the script's own hold TTL. When the script says it is holding, the job records
  the url and the script's pid in its meta (what `Server.Smoke` finds it by) and posts the url and the
  log's path on the thread; a smoke that fails posts its last lines instead. One attempt: a retry
  would stack another build.
  """
  use Oban.Worker, queue: :smoke, max_attempts: 1

  alias Server.Channel

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"thread_id" => tid, "ref" => ref}} = job) do
    log = Path.join(System.tmp_dir!(), "tlon-smoke-job-#{job.id}.log")
    bash = System.find_executable("bash")

    port =
      Port.open({:spawn_executable, bash}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, [Server.Smoke.script(), ref]},
        {:env, [{~c"TLON_SMOKE_HOLD", ~c"1"}]}
      ])

    # nil when the script already exited: its messages are still in the mailbox
    os_pid = with info when is_list(info) <- Port.info(port), do: info[:os_pid]
    code = pump(port, job, tid, os_pid, log, [])
    if code != 0, do: post(tid, "smoke of #{ref} ended (exit #{code}); the log: #{log}")
    :ok
  end

  defp pump(port, job, tid, os_pid, log, tail) do
    receive do
      {^port, {:data, {_eol, line}}} ->
        File.write!(log, [line, "\n"], [:append])
        hold(job, tid, os_pid, log, line)
        pump(port, job, tid, os_pid, log, Enum.take([line | tail], 12))

      {^port, {:exit_status, 0}} ->
        post(tid, "the held smoke is down")
        0

      {^port, {:exit_status, code}} ->
        post(tid, "smoke failed:\n" <> (tail |> Enum.reverse() |> Enum.join("\n")))
        code
    end
  end

  defp hold(job, tid, os_pid, log, line) do
    with [_, url] <- Regex.run(~r/^smoke: holding (http\S+) up/, line) do
      {:ok, _} =
        job
        |> Ecto.Changeset.change(meta: Map.merge(job.meta, %{"url" => url, "os_pid" => os_pid, "log" => log}))
        |> Server.Repo.update()

      post(
        tid,
        "the smoke is up at #{url} (log: #{log}). Drive it with drive_smoke(keys); stop_smoke when done. " <>
          "It tears itself down after the hold's TTL."
      )
    end
  end

  defp post(tid, body), do: {:ok, _} = Channel.post(%{thread_id: tid, author: "tlon", body: body})
end
