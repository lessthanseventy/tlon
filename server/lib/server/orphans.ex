defmodule Server.Orphans do
  @moduledoc """
  One seat, one session. A coworker's process carries its seat in its environment
  (`TLON_THREAD`, `TLON_AUTHOR`); one that outlives its window (tmux's kill-window hangs it up,
  and a harness may not exit on that) still holds the identity, still drains `Server.Wake`s keyed
  by it, and acts beside the session a respawn starts. `retire/3` signals those before the seat is
  taken again, so a handle on a thread has one process taking wakes.

  Only a process whose environment is readable and names both the thread and the handle is
  touched; the caller must have found the seat windowless first.
  """

  require Logger

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

  @doc "Signal every holder (SIGTERM unless `:kill` is given); how many were retired."
  def retire(thread_id, author, opts \\ []) do
    kill = Keyword.get(opts, :kill, &term/1)
    pids = holders(thread_id, author, opts)

    for pid <- pids do
      Logger.warning("retiring an earlier session of #{author} on ##{thread_id} (pid #{pid})")
      kill.(pid)
    end

    length(pids)
  end

  defp term(pid), do: System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
end
