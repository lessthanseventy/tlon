defmodule Server.Jobs.Smoke do
  @moduledoc """
  Runs `scripts/release-smoke.sh` on main's new tip after a landing
  (`Server.Smoke.queue_candidate/1`), from the service. The script records its `ran-on: smoke` for
  `Server.Release.Candidate`; a red one is the alarm's line. The job's meta carries the run's log.
  One attempt: a retry would stack another build.
  """
  use Oban.Worker, queue: :smoke, max_attempts: 1

  @log_ttl 7 * 86_400

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"candidate" => true, "ref" => ref}} = job) do
    case run(job, ref) do
      {_log, 0} -> :ok
      {log, code} -> {:error, "smoke of #{String.slice(ref, 0, 12)} failed (exit #{code}); the log: #{log}"}
    end
  end

  # a smoke about a thread is not run; quiet, so its ending posts no line on that thread
  def perform(%Oban.Job{args: %{"thread_id" => _}}), do: {:ok, :quiet}

  # the service runs under systemd, whose PATH has no mise shims: the script's bare `mix`/`bun` are
  # found through `mise exec`, from the checkout whose mise.toml pins them
  @doc false
  def launch([script | _] = argv) when is_binary(script) do
    case System.find_executable("mise") do
      nil -> {System.find_executable("bash"), argv}
      mise -> {mise, ["exec", "--", "bash" | argv]}
    end
  end

  defp script_root(script), do: script |> Path.dirname() |> Path.dirname()

  defp pump(port, log) do
    receive do
      {^port, {:data, {_eol, line}}} ->
        File.write!(log, [line, "\n"], [:append])
        pump(port, log)

      {^port, {:exit_status, code}} ->
        code
    end
  end

  defp state_home, do: System.get_env("XDG_STATE_HOME") || Path.join(System.user_home!(), ".local/state")

  defp prune(dir) do
    cutoff = System.os_time(:second) - @log_ttl

    for name <- File.ls!(dir) do
      path = Path.join(dir, name)

      with {:ok, %File.Stat{mtime: mtime}} <- File.stat(path, time: :posix), true <- mtime < cutoff do
        File.rm(path)
      end
    end
  end

  # the script to its exit, `{log, code}`
  defp run(job, ref) do
    dir = Path.join([state_home(), "tlon", "smoke"])
    File.mkdir_p!(dir)
    prune(dir)
    log = Path.join(dir, "smoke-job-#{job.id}.log")
    {exe, args} = launch([Server.Smoke.script(), ref])

    port =
      Port.open({:spawn_executable, exe}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:args, args},
        {:cd, script_root(Server.Smoke.script())},
        {:env, [{~c"MISE_YES", ~c"1"}]}
      ])

    {:ok, _} = job |> Ecto.Changeset.change(meta: Map.put(job.meta, "log", log)) |> Server.Repo.update()
    {log, pump(port, log)}
  end
end
