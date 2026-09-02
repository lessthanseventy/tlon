defmodule Console.CrashLogTest do
  @moduledoc """
  The crash log's path seam: test runs must never write the operator's real
  ~/.cache/aleph/crash.log (BoomProbe suites exercise the degrade-and-log paths on purpose),
  so `path/0` honors `:console, :crash_log_path` — test.exs points it at a scratch file.
  """
  use ExUnit.Case, async: false

  alias Console.CrashLog

  test "path/0 honors the :crash_log_path app env (test.exs points it at a scratch file)" do
    configured = Application.get_env(:console, :crash_log_path)
    assert is_binary(configured)
    assert CrashLog.path() == configured
    refute CrashLog.path() =~ ".cache/aleph"
  end

  test "path/0 falls back to the XDG cache location when unconfigured" do
    configured = Application.get_env(:console, :crash_log_path)
    Application.delete_env(:console, :crash_log_path)
    on_exit(fn -> Application.put_env(:console, :crash_log_path, configured) end)

    assert CrashLog.path() =~ Path.join("tlon", "crash.log")
  end

  test "append/2 writes header + body to the configured path" do
    p = CrashLog.path()
    File.rm(p)
    assert :ok = CrashLog.append("probe header", "probe body")
    content = File.read!(p)
    assert content =~ "=== probe header"
    assert content =~ "probe body"
  end
end
