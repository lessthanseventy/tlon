defmodule Server.Smoke do
  @moduledoc """
  The held smoke a QA seat drives, run by the service. `scripts/release-smoke.sh` needs Postgres's
  unix socket and a network namespace shared with the scratch node, which a seat's sandboxed Bash
  has neither of, so the seat asks and the service runs it (`Server.Jobs.Smoke`). The release
  script keeps its own one-smoke-per-commit lock; this module only finds the running one
  (an executing `Jobs.Smoke` whose meta carries the url) and stops it.
  """
  import Ecto.Query

  alias Server.Jobs.Smoke, as: Job

  @ref ~r|\A[A-Za-z0-9][A-Za-z0-9._/-]*\z|

  @doc "Queue the held smoke of `ref` (default the thread's own branch) for `thread`."
  @spec start(Server.Thread.t(), String.t() | nil) :: {:ok, Oban.Job.t()} | {:error, String.t()}
  def start(%Server.Thread{} = thread, ref) do
    ref = ref || "work/#{thread.slug}"

    cond do
      !Regex.match?(@ref, ref) -> {:error, "not a ref: #{inspect(ref)}"}
      held(thread.id) -> {:error, "a smoke is already up for this thread: #{held(thread.id).meta["url"]}"}
      true -> Oban.insert(Job.new(%{thread_id: thread.id, ref: ref}))
    end
  end

  @doc "The executing smoke job of `thread_id` that is up (its url known), or nil."
  @spec held(integer()) :: Oban.Job.t() | nil
  def held(thread_id) do
    Server.Repo.one(
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Smoke" and j.state == "executing" and
            fragment("?->>'thread_id' = ?", j.args, ^to_string(thread_id)) and
            fragment("?->>'url' is not null", j.meta),
        limit: 1
    )
  end

  @doc "Tear down the thread's held smoke: its script cleans up on TERM."
  @spec stop(integer()) :: :ok | {:error, String.t()}
  def stop(thread_id) do
    case held(thread_id) do
      nil ->
        {:error, "no smoke is up for this thread"}

      %{meta: %{"os_pid" => pid}} ->
        _ = System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true)
        :ok
    end
  end

  @doc """
  Drive the held smoke from the service: `scripts/office-drive.sh` with `keys`, the screen after
  each step. A seat's own drive is blind to the smoke's port (each sandboxed call has a network
  namespace of its own).
  """
  @spec drive(integer(), [String.t()]) :: {:ok, String.t()} | {:error, String.t()}
  def drive(thread_id, keys) do
    case held(thread_id) do
      nil ->
        {:error, "no smoke is up for this thread: start_smoke first"}

      %{meta: %{"url" => url}} ->
        script = Path.join(Server.Profiles.tlon_root(), "scripts/office-drive.sh")
        task = Task.async(fn -> System.cmd(script, keys, env: [{"TLON_URL", url}], stderr_to_stdout: true) end)

        case Task.yield(task, 180_000) || Task.shutdown(task, :brutal_kill) do
          {:ok, {out, _code}} -> {:ok, out}
          _ -> {:error, "the drive did not finish in 3 minutes"}
        end
    end
  end

  @doc "The script that builds and holds the smoke (`config :server, :smoke_script` in tests)."
  def script,
    do:
      Application.get_env(:server, :smoke_script) || Path.join(Server.Profiles.tlon_root(), "scripts/release-smoke.sh")
end
