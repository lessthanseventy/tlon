defmodule Server.Smoke do
  @moduledoc """
  The held smoke a QA seat drives, run by the service. `scripts/release-smoke.sh` needs Postgres's
  unix socket and a network namespace shared with the scratch node, which a seat's sandboxed Bash
  has neither of, so the seat asks and the service runs it (`Server.Jobs.Smoke`). The release
  script keeps its own one-smoke-per-commit lock; this module only finds the thread's job and
  stops it: `held/1` is the one up (its url in meta), `building/2` the one queued or still building
  (no url yet) — drive says so and a start for the same commit returns it (the ref is resolved to its
  sha at start; a ref whose tip moved cancels the old build and queues the new one); stop TERMs its script once it has a
  pid, or cancels the job when it has no process yet.
  """
  import Ecto.Query

  alias Server.Jobs.Smoke, as: Job

  @building_minutes 20

  @ref ~r|\A[A-Za-z0-9](?:[A-Za-z0-9._/-]*[A-Za-z0-9._-])?\z|
  @name ~r/\A[a-z][a-z0-9_]*\z/
  # a fixture is a name, then optionally `:key=value,key=value` (no spaces: TLON_SMOKE_FIXTURES is split on them)
  @fixture ~r/\A[a-z][a-z0-9_]*(?::[a-z][a-z0-9_]*=[A-Za-z0-9_.-]+(?:,[a-z][a-z0-9_]*=[A-Za-z0-9_.-]+)*)?\z/

  @old_hold_note "(old hold: driving the checkout's office-drive.sh)\n"

  @doc """
  Queue the held smoke of `ref` (default the thread's own branch) for `thread`. `fixtures` are
  checked here by grammar only: the catalog that knows them is the candidate's
  (`Server.Smoke.Fixtures`, applied by the script on the smoke node).
  """
  @spec start(Server.Thread.t(), String.t() | nil) :: {:ok, Oban.Job.t()} | {:error, String.t()}
  def start(%Server.Thread{} = thread, ref, by \\ nil, flags \\ [], fixtures \\ []) do
    ref = ref || (thread.slug && "work/#{thread.slug}")

    cond do
      is_nil(ref) ->
        {:error, "no ref: the thread has no slug to name its work/ branch"}

      !Regex.match?(@ref, ref) ->
        {:error, "not a ref: #{inspect(ref)}"}

      Enum.any?(flags, &(!Regex.match?(@name, &1))) ->
        {:error, "not a flag name: #{inspect(flags)}"}

      Enum.any?(fixtures, &(!Regex.match?(@fixture, &1))) ->
        {:error, "not a fixture name: #{inspect(fixtures)}"}

      held(thread.id) ->
        {:error, "a smoke is already up for this thread: #{held(thread.id).meta["url"]}"}

      true ->
        queue(thread.id, ref, %{by: by, flags: flags, fixtures: fixtures})
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

  @doc """
  The thread's smoke job that is queued or running but not up yet (no url), or nil; with `ref`,
  only one of that ref. A start for the same commit returns it rather than stacking a second
  build; a start over a moved tip replaces it.
  A job queued over `@building_minutes` ago is a stuck build, not a building one.
  """
  @spec building(integer(), String.t() | nil) :: Oban.Job.t() | nil
  def building(thread_id, ref \\ nil) do
    query =
      from j in Oban.Job,
        where:
          j.worker == "Server.Jobs.Smoke" and j.state in ["available", "scheduled", "executing"] and
            j.inserted_at > ago(@building_minutes, "minute") and
            fragment("?->>'thread_id' = ?", j.args, ^to_string(thread_id)) and
            fragment("?->>'url' is null", j.meta),
        order_by: j.id,
        limit: 1

    Server.Repo.one(if ref, do: where(query, [j], fragment("?->>'ref' = ?", j.args, ^ref)), else: query)
  end

  @doc """
  Tear down the thread's smoke, up or still building: its script cleans up on TERM. A queued job
  with no process yet is cancelled instead.
  """
  @spec stop(integer()) :: :ok | {:error, String.t()}
  def stop(thread_id) do
    case held(thread_id) || building(thread_id) do
      nil -> {:error, "no smoke is up for this thread"}
      job -> stop_job(job)
    end
  end

  @doc """
  Drive the held smoke from the service: `scripts/office-drive.sh` with `keys`, the screen after
  each step. A seat's own drive is blind to the smoke's port (each sandboxed call has a network
  namespace of its own).
  """
  @spec drive(integer(), [String.t()], keyword()) :: {:ok, String.t()} | {:error, String.t()}

  def drive(thread_id, keys, opts \\ []) do
    case held(thread_id) do
      nil ->
        {:error, none(thread_id, "no smoke is up for this thread: start_smoke first")}

      %{meta: %{"url" => url} = meta} ->
        # the smoke's own build dir, so a TUI change drives the candidate's TUI (old holds: the checkout)
        dir = meta["dir"] || Server.Profiles.tlon_root()
        {exe, args} = Job.launch([Path.join(dir, "scripts/office-drive.sh") | keys])
        env = [{"TLON_URL", url}, {"MISE_YES", "1"} | drive_env(opts)]
        task = Task.async(fn -> System.cmd(exe, args, cd: dir, env: env, stderr_to_stdout: true) end)

        case Task.yield(task, 180_000) || Task.shutdown(task, :brutal_kill) do
          {:ok, {out, _code}} -> {:ok, if(meta["dir"], do: out, else: @old_hold_note <> out)}
          _ -> {:error, "the drive did not finish in 3 minutes"}
        end
    end
  end

  @doc "The script that builds and holds the smoke (`config :server, :smoke_script` in tests)."
  def script do
    Application.get_env(:server, :smoke_script) || script_in_main_root()
  end

  defp script_in_main_root do
    {:ok, root} = Server.Profiles.main_root()
    Path.join(root, "scripts/release-smoke.sh")
  end

  defp building_error(%Oban.Job{id: id} = job, fallback) do
    since = Calendar.strftime(job.attempted_at || job.inserted_at, "%H:%M:%SZ")
    "building since #{since} (job #{id}): #{fallback}"
  end

  defp none(thread_id, fallback) do
    case building(thread_id) do
      nil -> fallback
      job -> building_error(job, "its url is posted on the thread when it is up")
    end
  end

  defp queue(thread_id, ref, opts) do
    with {:ok, sha} <- resolve(ref) do
      case building(thread_id, ref) do
        nil -> insert(thread_id, ref, sha, opts, %{})
        %{args: %{"sha" => ^sha}} = job -> {:ok, job}
        old -> replace(old, thread_id, ref, sha, opts)
      end
    end
  end

  # the tip moved since the building job was queued: that build is of a commit nobody asked for now
  defp replace(old, thread_id, ref, sha, opts) do
    case stop_job(old) do
      :ok ->
        insert(thread_id, ref, sha, opts, %{"replaced" => old.id})

      {:error, _} ->
        {:error,
         "the tip of #{ref} moved, but the old build (job #{old.id}) can't be cancelled until its script starts: start again in a moment"}
    end
  end

  defp insert(thread_id, ref, sha, opts, meta) do
    args = Map.reject(Map.merge(opts, %{thread_id: thread_id, ref: ref, sha: sha}), fn {_k, v} -> v in [nil, []] end)
    Oban.insert(Job.new(args, meta: meta))
  end

  # the commit `ref` names right now, in the git dir every thread worktree shares; a ref not fetched
  # is refused, not fetched, in the request path (`config :server, :smoke_resolve` in tests)
  defp resolve(ref) do
    resolver = Application.get_env(:server, :smoke_resolve, &resolve_in_main_root/1)

    case resolver.(ref) do
      {:ok, sha} -> {:ok, sha}
      _ -> {:error, "no commit #{ref}"}
    end
  end

  defp resolve_in_main_root(ref) do
    with {:ok, root} <- Server.Profiles.main_root(),
         {out, 0} <-
           System.cmd("git", ["-C", root, "rev-parse", "-q", "--verify", "#{ref}^{commit}"], stderr_to_stdout: true) do
      {:ok, String.trim(out)}
    else
      _ -> :error
    end
  end

  # wide: the wide room in half blocks (where events, the door and the pets are), read as text lines;
  # sandbox: the made-up world, where the toy's keys (E, F, D, T) run
  defp drive_env(opts) do
    wide = if opts[:wide], do: [{"OFFICE_WIDE", "1"}, {"OFFICE_TEXT", "1"}], else: []
    if opts[:sandbox], do: [{"OFFICE_SANDBOX", "1"} | wide], else: wide
  end

  defp stop_job(%{meta: %{"os_pid" => pid}}) when is_integer(pid) do
    _ = System.cmd("kill", ["-TERM", to_string(pid)], stderr_to_stdout: true)
    :ok
  end

  defp stop_job(%{state: state, id: id}) when state in ["available", "scheduled"], do: Oban.cancel_job(id)

  defp stop_job(job), do: {:error, building_error(job, "its script has not started yet; stop again in a moment")}
end
