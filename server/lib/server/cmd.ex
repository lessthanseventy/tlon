defmodule Server.Cmd do
  @moduledoc """
  `System.cmd/3` with a wall. A `git` or `gh` that hangs (a locked keyring under `gh`, a remote
  that never answers) held the single-concurrency landing and maintain queues until Oban's
  Lifeline rescued the job hours later; here it ends with exit 124 and its output saying so, which
  every caller already reads as a failure. `opts[:timeout]` is seconds (default `:cmd_timeout_s`,
  120); `:infinity` runs unbounded, for a command that carries its own wall. The signature and the
  `{out, code}` answer are `System.cmd/3`'s, so it is the default `run` wherever one is injected. A
  command not on PATH is exit 127 here, not a raise.
  """

  @default_s 120

  @doc "Run `cmd` with `args`, cut off after `opts[:timeout]` seconds."
  @spec run(binary(), [binary()], keyword()) :: {Collectable.t(), non_neg_integer()}
  def run(cmd, args, opts \\ []) do
    {timeout, opts} = Keyword.pop(opts, :timeout, Application.get_env(:server, :cmd_timeout_s, @default_s))

    case timeout do
      :infinity ->
        System.cmd(cmd, args, opts)

      seconds when is_integer(seconds) and seconds > 0 ->
        case System.cmd("timeout", ["-k", "5", to_string(seconds), cmd | args], opts) do
          {out, 124} -> {out <> "\n(#{cmd} #{List.first(args)} timed out after #{seconds} s)", 124}
          done -> done
        end
    end
  end
end
