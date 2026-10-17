defmodule Server.Orphans do
  @moduledoc """
  One seat, one session. A coworker's process carries its seat in its environment
  (`TLON_THREAD`, `TLON_AUTHOR`); one that outlives its window (tmux's kill-window hangs it up,
  and a harness may not exit on that) still holds the identity, still drains `Server.Wake`s keyed
  by it, and acts beside the session a respawn starts. `retire/3` signals those before the seat is
  taken again, so a handle on a thread has one process taking wakes: SIGTERM, then SIGKILL for any
  still holding the identity after a grace period, and a notice on the thread saying so.

  Only a process whose environment is readable and names both the thread and the handle is
  touched; the caller must have found the seat windowless first.
  """

  require Logger

  @grace_ms 3_000

  @doc "Pids whose environment holds `TLON_THREAD=thread_id` and `TLON_AUTHOR=author`, sorted; never this node's own."
  def holders(thread_id, author, opts \\ []) do
    proc = Keyword.get(opts, :proc_dir, "/proc")
    mine = String.to_integer(System.pid())
    want = ["TLON_THREAD=#{thread_id}", "TLON_AUTHOR=#{author}"]

    proc
    |> File.ls()
    |> case do
      {:ok, names} -> names
      _ -> []
    end
    |> Enum.flat_map(fn name ->
      with {pid, ""} <- Integer.parse(name),
           true <- pid != mine,
           {:ok, env} <- File.read(Path.join([proc, name, "environ"])),
           true <- want -- String.split(env, <<0>>, trim: true) == [] do
        [pid]
      else
        _ -> []
      end
    end)
    |> Enum.sort()
  end

  @doc """
  Signal every holder (SIGTERM unless `:kill` is given), wait up to `:grace` ms (3000) for them to
  let go of the identity, SIGKILL (`:force`) whoever has not, and say so on the thread
  (`:notify`, a one-arg function of the notice text; default a `notice` post from `tlon`).
  How many were retired.
  """
  def retire(thread_id, author, opts \\ []) do
    kill = Keyword.get(opts, :kill, &term/1)
    force = Keyword.get(opts, :force, &sigkill/1)
    notify = Keyword.get(opts, :notify, &post_notice(thread_id, &1))
    pids = holders(thread_id, author, opts)

    for pid <- pids do
      Logger.warning("retiring an earlier session of #{author} on ##{thread_id} (pid #{pid})")
      kill.(pid)
    end

    if pids != [] do
      stuck = await_release(pids, thread_id, author, opts, Keyword.get(opts, :grace, @grace_ms))

      for pid <- stuck do
        Logger.warning("pid #{pid} ignored SIGTERM and still holds #{author} on ##{thread_id}; SIGKILL")
        force.(pid)
      end

      notify.(notice(author, pids, stuck))
    end

    length(pids)
  end

  defp await_release(pids, thread_id, author, opts, grace) do
    left = Enum.filter(holders(thread_id, author, opts), &(&1 in pids))

    if left == [] or grace <= 0 do
      left
    else
      Process.sleep(min(grace, 50))
      await_release(pids, thread_id, author, opts, grace - 50)
    end
  end

  defp notice(author, pids, stuck) do
    "retired #{length(pids)} earlier session(s) of #{author} still holding this seat (pid #{Enum.join(pids, ", ")})" <>
      if(stuck == [], do: "", else: "; SIGKILL for the ones that ignored SIGTERM (pid #{Enum.join(stuck, ", ")})")
  end

  defp post_notice(thread_id, body) do
    if Server.Repo.get(Server.Thread, thread_id),
      do: Server.Channel.post(%{thread_id: thread_id, author: "tlon", kind: "notice", body: body})
  end

  defp term(pid), do: System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
  defp sigkill(pid), do: System.cmd("kill", ["-KILL", Integer.to_string(pid)], stderr_to_stdout: true)
end
