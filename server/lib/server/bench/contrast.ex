defmodule Server.Bench.Contrast do
  @moduledoc """
  The canary A/B a steering change earns on verify: the same role, the same canary tasks, once from
  main's checkout and once from the branch's, and what the contrast was (pass count, tokens, turns).
  Evidence, not a gate: a regression is named for the reviewer (`line/1` ends `REGRESSION`) and never
  turns verify red. Pure rows here; `run/3` shells out to `mix server.bench_roles`, each side in its
  own process group under one 15-minute wall (`sh/3`), so nothing a side spawned outlives it.
  """

  alias Server.Workline.Grade

  @max_roles 3
  @wall_ms 15 * 60_000

  @doc """
  The rows for a change touching `paths`; `dirs` = `%{main: checkout, branch: checkout}` (main's a
  throwaway worktree of origin/main, never the root checkout). `[]` when it touches no steering.
  `opts[:exec]` swaps the shell-out (`(dir, args, timeout_ms) -> {output, exit | :timeout}`; the
  default runs `mix` in `<dir>/server` through `sh/3`). `opts[:wall_ms]` is the run's one clock
  (15 minutes): every call gets what is left of it, and a side that hits it is an error row.
  """
  def run(paths, dirs, opts \\ []) do
    exec = opts[:exec] || (&mix/3)
    deadline = System.monotonic_time(:millisecond) + (opts[:wall_ms] || @wall_ms)
    steering = Grade.steering(paths)
    profiles? = Enum.any?(steering, &match?({:profiles, _}, &1))
    unmeasured = for {:unmeasurable, p} <- steering, do: p
    extra = if unmeasured == [], do: [], else: [unmeasurable(unmeasured)]

    if profiles?, do: bench(dirs, {exec, deadline}) ++ extra, else: extra
  end

  @doc """
  `argv` run in `dir` as its own process group: `{output, exit}`. Past `timeout_ms` the whole group
  is killed and the exit is `:timeout` — a bench's mix, and the claude runs it spawned, never outlive
  the wall. The VM starts a port program as the leader of a new group (so a `setsid` here would fork
  it away and return at once), which is what makes the port's pid the group's.
  """
  def sh([exe | args], dir, timeout_ms) do
    port =
      Port.open({:spawn_executable, System.find_executable(exe) || exe}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        cd: dir
      ])

    # nil when the side already exited and the port closed with it: its exit is in the mailbox and
    # there is nothing left to kill
    pid = with {:os_pid, pid} <- Port.info(port, :os_pid), do: pid
    collect(port, pid, [], System.monotonic_time(:millisecond) + timeout_ms)
  end

  @doc "Roles whose prompt hash differs between main and the branch (or is new on it), sorted."
  def affected(main_fp, branch_fp) do
    Enum.sort(for({role, h} <- branch_fp, Map.get(main_fp, role) != h, do: role))
  end

  @doc "`{run, skipped}`: the first `n` roles and the rest."
  def cap(roles, n \\ @max_roles), do: Enum.split(roles, n)

  @doc "One side's decoded run records → passes, tokens (in+out), turns, commit."
  def summarize(records) do
    tasks = Enum.flat_map(records, & &1["tasks"])

    %{
      passed: Enum.count(tasks, & &1["passed"]),
      total: length(tasks),
      tokens: records |> Enum.map(&(&1["usage"]["input"] + &1["usage"]["output"])) |> Enum.sum(),
      turns: tasks |> Enum.map(&(&1["usage"]["turns"] || 0)) |> Enum.sum(),
      commit: records |> List.first() |> then(&(&1 && &1["commit"]))
    }
  end

  @doc "The contrast row for `role`: both sides summarized; an empty side is an `error`, never a regression."
  def row(role, main_records, branch_records) do
    {m, b} = {summarize(main_records), summarize(branch_records)}
    ok? = m.total > 0 and b.total > 0

    %{
      kind: :contrast,
      role: role,
      status: if(ok?, do: "ok", else: "error"),
      main: m,
      branch: b,
      regression: ok? and b.passed < m.passed
    }
  end

  def unmeasurable(paths), do: %{kind: :unmeasurable, paths: paths}
  def skipped(roles), do: %{kind: :skipped, roles: roles}
  def error(why), do: %{kind: :error, why: why}

  @doc "The row as the one line recorded as CHECKS evidence and posted to the thread."
  def line(%{kind: :contrast, status: "error", role: r}), do: "bench_contrast #{r}: error — a side ran no tasks"

  def line(%{kind: :contrast, role: r, main: m, branch: b, regression: reg}) do
    "bench_contrast #{r}: main #{m.passed}/#{m.total} · branch #{b.passed}/#{b.total} · " <>
      "tokens #{m.tokens}/#{b.tokens} · turns #{m.turns}/#{b.turns} · #{m.commit}..#{b.commit}" <>
      if(reg, do: " · REGRESSION", else: "")
  end

  def line(%{kind: :unmeasurable, paths: p}),
    do: "bench_contrast unmeasurable: #{Enum.join(p, ", ")} — a seat reads it, the bench never loads it"

  def line(%{kind: :skipped, roles: r}),
    do: "bench_contrast skipped: #{Enum.join(r, ", ")} — over the #{@max_roles}-role cap"

  def line(%{kind: :error, why: w}), do: "bench_contrast error: #{w}"

  defp bench(dirs, exec) do
    with {:ok, main_fp} <- json(exec, dirs.main, ["--fingerprint"]),
         {:ok, branch_fp} <- json(exec, dirs.branch, ["--fingerprint"]) do
      {roles, over} = main_fp |> affected(branch_fp) |> cap()
      Enum.map(roles, &contrast(dirs, exec, &1)) ++ if(over == [], do: [], else: [skipped(over)])
    else
      {:error, why} -> [error(why)]
    end
  end

  # one role, both sides; a side that failed to run names itself in the error row
  defp contrast(dirs, exec, role) do
    args = ["--suite", "canary", "--role", role]

    case {json(exec, dirs.main, args), json(exec, dirs.branch, args)} do
      {{:ok, m}, {:ok, b}} -> row(role, m, b)
      {m, b} -> error(String.trim("#{role}: #{why(m)} #{why(b)}"))
    end
  end

  defp why({:error, w}), do: w
  defp why(_), do: ""

  # one `mix server.bench_roles <args> --out FILE` in `dir` with what is left of the wall, its JSON read back
  defp json({exec, deadline}, dir, args) do
    out = Path.join(System.tmp_dir!(), "contrast-#{System.unique_integer([:positive])}.json")
    call = "#{Path.basename(dir)}: bench_roles #{Enum.join(args, " ")}"
    wall = "the #{div(@wall_ms, 60_000)}-minute wall"
    left = deadline - System.monotonic_time(:millisecond)

    try do
      if left <= 0 do
        {:error, "#{call} not run: #{wall} is spent"}
      else
        case exec.(dir, ["server.bench_roles" | args] ++ ["--out", out], left) do
          {_, 0} ->
            {:ok, out |> File.read!() |> JSON.decode!()}

          {_, :timeout} ->
            {:error, "#{call} hit #{wall}: its process group killed"}

          {text, code} ->
            tail = text |> to_string() |> String.slice(-200, 200)
            {:error, "#{call} exit #{code}: #{tail}"}
        end
      end
    after
      File.rm(out)
    end
  end

  defp mix(dir, args, timeout_ms), do: sh(["mise", "exec", "--", "mix" | args], Path.join(dir, "server"), timeout_ms)

  # a side still writing past the deadline is cut too: its data is left unread
  defp collect(port, pid, acc, deadline) do
    left = deadline - System.monotonic_time(:millisecond)

    receive do
      {^port, {:data, data}} when left > 0 -> collect(port, pid, [acc | data], deadline)
      {^port, {:exit_status, code}} -> {IO.iodata_to_binary(acc), code}
    after
      max(left, 0) ->
        if pid, do: System.cmd("kill", ["-KILL", "--", "-#{pid}"], stderr_to_stdout: true)
        close(port)
        {IO.iodata_to_binary(acc), :timeout}
    end
  end

  # the child may have exited between the kill and this, closing the port itself
  defp close(port) do
    Port.close(port)
  catch
    :error, :badarg -> :ok
  end
end
