defmodule Console.CrashLog do
  @moduledoc """
  Append-only failure log at `$XDG_CACHE_HOME/tlon/crash.log` (else `~/.cache`). console holds the
  TTY in the alt-screen, which swallows a crash's stderr — this leaves the trace on disk so a
  failure (a cockpit crash, a panel render raise) is readable after the fact instead of vanishing.
  """

  @spec path() :: String.t()
  def path do
    # :crash_log_path (test.exs) points suites that exercise the degrade-and-log paths on
    # purpose (BoomProbe) at a scratch file, so they never pollute the operator's real log.
    Application.get_env(:console, :crash_log_path) || default_path()
  end

  defp default_path do
    cache = System.get_env("XDG_CACHE_HOME") || Path.join(System.user_home!(), ".cache")
    Path.join([cache, "tlon", "crash.log"])
  end

  @doc "Append a timestamped `header`/`body` entry. Best-effort — a log-write failure never propagates."
  @spec append(String.t(), String.t()) :: :ok
  def append(header, body) do
    p = path()
    stamp = DateTime.to_iso8601(DateTime.utc_now())
    _ = File.mkdir_p(Path.dirname(p))
    _ = File.write(p, "=== #{header} #{stamp} ===\n#{body}\n\n", [:append])
    :ok
  rescue
    _ -> :ok
  end
end
