defmodule Console.Cockpit.Recovery do
  @moduledoc """
  The run loop around the cockpit GenServer: start it, wait for it to go DOWN, restore the host
  tty, log (and file as a server issue) a crash, and decide whether to relaunch in place — up to
  `@resurrect_max_fails` rapid crashes before staying down so a persistent bad state can't spin
  the terminal. A run that survived `@resurrect_healthy_ms` counts as healthy: its next crash
  starts the count over.
  """

  alias Console.Safe
  alias Server.Channel
  alias Server.Dossier

  @resurrect_max_fails 3
  @resurrect_healthy_ms 5_000

  @kitty_disable "\e[<u"
  @paste_disable "\e[?2004l"

  @doc """
  Start the cockpit and block until the operator quits. `strikes` = consecutive rapid crashes so
  far. The cockpit is an unlinked, monitored GenServer — its crash surfaces here as a clean DOWN (a
  linked exit would kill this task before it restored the terminal). server (Repo/Bus) and the
  session terminals are supervised and keep running, so a crash relaunches a FRESH cockpit in place
  — a reconnect, not a cold boot — unless it's looping.
  """
  @spec run(non_neg_integer()) :: :ok
  def run(strikes \\ 0) do
    case GenServer.start(Console.Cockpit, %{}) do
      {:ok, pid} ->
        ref = Process.monitor(pid)
        started = System.monotonic_time(:millisecond)

        receive do
          {:DOWN, ^ref, :process, ^pid, reason} ->
            restore_host_tty()
            # Capture a crashed exit — the alt-screen otherwise swallows it silently. (No-op on a
            # clean quit, so a normal `q` never spams the log.)
            log_crash(reason)
            act_on(resurrect_decision(reason, strikes, System.monotonic_time(:millisecond) - started, stdio_alive?()))
        end

      {:error, {:tb_init_failed, code}} ->
        note("console needs a real terminal (tb_init returned #{code}) — run this in ghostty.")
        :ok

      {:error, reason} ->
        note("console failed to start: #{inspect(reason)}")
        :ok
    end
  end

  @doc """
  The recovery decision after a cockpit goes DOWN. Pure so it's unit-tested without a TTY:

    * `:quit` — a clean operator quit (`:normal` / `:shutdown`), end the session.
    * `{:resurrect, n}` — a crash; relaunch, now on strike n.
    * `{:stop, n}` — the nth crash in a row hit the ceiling; stay down.
    * `:dead_io` — a crash, but `:standard_io` died with it; a relaunch would raise on init's
      alt-screen writes, so stay down.

  `crash_report/1` is the clean-vs-crash oracle (nil = normal/shutdown). A run that lasted at
  least `@resurrect_healthy_ms` resets the strike count, so an isolated crash always heals.
  """
  @spec resurrect_decision(term(), non_neg_integer(), integer(), boolean()) ::
          :quit | :dead_io | {:resurrect, pos_integer()} | {:stop, pos_integer()}
  def resurrect_decision(reason, prev_strikes, alive_ms, io_alive? \\ true) do
    cond do
      is_nil(crash_report(reason)) ->
        :quit

      not io_alive? ->
        :dead_io

      true ->
        strikes = if alive_ms >= @resurrect_healthy_ms, do: 1, else: prev_strikes + 1
        if strikes >= @resurrect_max_fails, do: {:stop, strikes}, else: {:resurrect, strikes}
    end
  end

  # :io requests to a dead device return {:error, :terminated} instead of raising — the probe a
  # resurrect runs before writing anything to :standard_io again.
  defp stdio_alive?, do: match?(opts when is_list(opts), :io.getopts(:standard_io))

  # stdout can be dead after a host-side teardown — a status line is never worth a second crash
  # in the recovery path. stdout, not stderr: `console:run` parks fd 2 in a log file while the
  # cockpit runs (see mise.toml), so stderr never reaches the operator's screen.
  defp note(msg), do: Safe.value(fn -> IO.puts(msg) end, :ok)

  defp act_on(:quit), do: :ok

  defp act_on(:dead_io) do
    Console.CrashLog.append("resurrect skipped", "stdio died with the cockpit — staying down")
    note("console crashed and its terminal is gone — staying down. Trace: #{Console.CrashLog.path()}")
    :ok
  end

  defp act_on({:stop, n}) do
    note("console crashed #{n}× in a row — staying down. Trace: #{Console.CrashLog.path()}")
    :ok
  end

  defp act_on({:resurrect, n}) do
    note("console crashed — recovering in place… (#{n}/#{@resurrect_max_fails})")
    run(n)
  end

  @doc """
  Pop the Kitty keyboard flags and bracketed paste. Straight to /dev/tty, not stdout — the io server
  may already be winding down on a crash. Teardown runs it while still ON the alt screen (the two
  screens keep independent keyboard-flag stacks).
  """
  @spec pop_modes() :: :ok
  def pop_modes do
    _ = File.write("/dev/tty", @kitty_disable <> @paste_disable)
    :ok
  end

  @doc """
  Force-disarm everything a dead cockpit could have left armed: Kitty pop (no-op on an empty
  stack), mouse reporting off, leave alt screen, show cursor. Idempotent — run/1 also calls this
  after a DOWN, so even a killed GenServer leaves a working shell, not `;5u` keystroke garbage.
  """
  @spec restore_host_tty() :: :ok
  def restore_host_tty do
    _ = File.write("/dev/tty", @kitty_disable <> @paste_disable <> "\e[?1000;1002;1003;1006l\e[?1049l\e[?25h")
    :ok
  end

  @doc "A formatted crash report for a non-normal DOWN reason, or nil for a clean quit (never logged)."
  @spec crash_report(term()) :: String.t() | nil
  def crash_report(reason) when reason in [:normal, :shutdown], do: nil
  def crash_report({:shutdown, _}), do: nil
  def crash_report(reason), do: Exception.format_exit(reason)

  # Append a crashed exit to the crash log and echo it to stdout after the tty is restored, so it
  # doesn't get swallowed by the alt-screen. Best-effort: a log write failure never masks the crash.
  defp log_crash(reason) do
    with report when is_binary(report) <- crash_report(reason) do
      Safe.value(
        fn ->
          Console.CrashLog.append("console crash", report)
          IO.puts("console crashed (logged to #{Console.CrashLog.path()}):\n#{report}")
          file_crash_issue(report)
        end,
        :ok
      )
    end

    :ok
  end

  @doc "The first report line, trimmed — the filed issue's title."
  @spec crash_summary(String.t()) :: String.t()
  def crash_summary(report) do
    report |> String.split("\n", trim: true) |> List.first("a cockpit crash") |> String.slice(0, 120)
  end

  # A crashed cockpit files a server issue on the machine thread — its own failures become tracked,
  # triageable work in the system it renders, not just a log line. Deduped against the thread's open
  # issues so a crash loop files one, not a hundred. Best-effort: no server (down, or the crash took
  # it too) just means the crash log is the only record.
  defp file_crash_issue(report) do
    summary = "console crashed: " <> crash_summary(report)

    Safe.value(
      fn ->
        with %{id: id} = thread <- Channel.machine_thread(),
             false <- crash_issue_open?(Dossier.open_issues_for_thread(thread), summary) do
          Dossier.raise_issue(%{thread_id: id, summary: summary, evidence: report, found_by: "console"})
        end
      end,
      :ok
    )
  end

  @doc """
  Is a crash issue with this summary already open on the thread? `open_issues_for_thread` returns
  the capped `%{shown, more}` shape, NOT a bare list — enumerating the map would raise inside the
  best-effort guard and silently never file. Public so the shape contract is pinned.
  """
  @spec crash_issue_open?(%{shown: [map()]}, String.t()) :: boolean()
  def crash_issue_open?(%{shown: shown}, summary), do: Enum.any?(shown, &(&1.summary == summary))
end
