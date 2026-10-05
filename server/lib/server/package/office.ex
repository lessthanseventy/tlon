defmodule Server.Package.Office do
  @moduledoc """
  A build step of the `tlon` release (`mise run server:package`): before each target's launcher is
  built, compile the office TUI (`../office`) for that target with bun, and stage it xz-compressed at
  `rel/burrito/office.xz`, where the launcher plugin (`rel/burrito/plugin.zig`) embeds it. So
  `tlon office` is the TUI from the one file, exec'd before the VM ever starts — with the real
  terminal, which a program started from inside the VM never has.
  """
  @behaviour Burrito.Builder.Step

  @impl true
  def execute(%{target: target} = context) do
    bun_target = "bun-#{os(target.os)}-#{cpu(target.cpu)}"
    tui = Path.join(System.tmp_dir!(), "tlon-office-#{bun_target}")
    staged = Path.expand("rel/burrito/office.xz")

    run!("bun", ["build", "--compile", "--minify", "--target=#{bun_target}", "tui/main.ts", "--outfile", tui],
      cd: Path.expand("../office")
    )

    run!("sh", ["-c", ~s(xz -9 -T0 -c "$1" > "$2"), "sh", tui, staged], [])
    context
  end

  defp run!(cmd, args, opts) do
    case System.cmd(cmd, args, [stderr_to_stdout: true] ++ opts) do
      {_, 0} -> :ok
      {out, code} -> Mix.raise("office TUI for the tlon release: #{cmd} exited #{code}\n#{out}")
    end
  end

  defp os(:darwin), do: "darwin"
  defp os(:linux), do: "linux"
  defp cpu(:x86_64), do: "x64"
  defp cpu(:aarch64), do: "arm64"
end
