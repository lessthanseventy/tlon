defmodule Server.Git do
  @moduledoc """
  `git -C repo …` through `Server.Cmd` (bounded, stderr in the output): the one shape the nine
  private `git/2` helpers were each re-implementing.
  """

  @doc "`{out, code}`, as `System.cmd/3` answers."
  @spec cmd(binary(), [binary()], keyword()) :: {binary(), non_neg_integer()}
  def cmd(repo, args, opts \\ []),
    do: Server.Cmd.run("git", ["-C", repo | args], Keyword.merge([stderr_to_stdout: true], opts))

  @doc "`{:ok, trimmed}` on exit 0, else `{:error, trimmed}`."
  @spec run(binary(), [binary()], keyword()) :: {:ok, binary()} | {:error, binary()}
  def run(repo, args, opts \\ []) do
    case cmd(repo, args, opts) do
      {out, 0} -> {:ok, String.trim(out)}
      {out, _} -> {:error, String.trim(out)}
    end
  end
end
