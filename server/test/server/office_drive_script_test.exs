defmodule Server.OfficeDriveScriptTest do
  # scripts/office-drive.sh runs the TUI under a throwaway XDG_STATE_HOME, which hides mise's trust db from
  # the `bun` shim; the drive must run the real binary. A stub shim fails the way mise does when it runs
  # under that state dir.
  use ExUnit.Case, async: true

  @drive Path.expand("../../../scripts/office-drive.sh", __DIR__)

  setup do
    tmp = Path.join(System.tmp_dir!(), "office-drive-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "bin"))
    on_exit(fn -> File.rm_rf!(tmp) end)
    real = Path.join(tmp, "real-bun")

    stub(Path.join(tmp, "bin/bun"), """
    [ "$1" = -e ] && { echo '#{real}'; exit 0; }
    [ -n "$XDG_STATE_HOME" ] && { echo 'mise ERROR Config files in ~/tlon/mise.toml are not trusted' >&2; exit 1; }
    """)

    %{tmp: tmp, real: real}
  end

  defp stub(path, body) do
    File.write!(path, "#!/bin/sh\n" <> body)
    File.chmod!(path, 0o755)
  end

  defp drive(ctx) do
    System.cmd("bash", [@drive, "wait:started"],
      env: [
        {"PATH", Path.join(ctx.tmp, "bin") <> ":" <> System.get_env("PATH")},
        {"TMUX_TMPDIR", ctx.tmp},
        {"TMPDIR", ctx.tmp},
        {"OFFICE_SANDBOX", "1"},
        {"XDG_STATE_HOME", nil}
      ],
      stderr_to_stdout: true
    )
  end

  test "the TUI runs on the real bun, not the shim that needs mise's trust db", ctx do
    stub(ctx.real, "echo started; sleep 5")
    assert {out, 0} = drive(ctx)
    assert out =~ "started"
    refute out =~ "not trusted"
  end

  test "a TUI that wrote to stderr fails the drive", ctx do
    stub(ctx.real, "echo boom >&2")
    assert {out, 1} = drive(ctx)
    assert out =~ "boom"
  end
end
