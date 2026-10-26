defmodule Mix.Tasks.Server.BenchContrast do
  @shortdoc "Canary A/B for a branch's steering edits — --branch DIR --main DIR; prints one evidence line per row"
  @moduledoc """
  #{@shortdoc}. What the branch changed against `origin/main` decides (`Server.Workline.Grade.steering/1`):
  a branch that touches no steering prints nothing and runs nothing. Canary tier only, at most 3 roles,
  under one 15-minute wall that kills a side's whole process group (`Server.Bench.Contrast`). Called by
  `scripts/workline-verify.sh` with `--main` a throwaway worktree of origin/main, never red: it always
  exits 0.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Bench.Contrast

  @impl Mix.Task
  def run(argv) do
    {opts, _} = OptionParser.parse!(argv, strict: [branch: :string, main: :string])
    branch = opts[:branch] || Mix.raise("--branch DIR is required")
    main = opts[:main] || Mix.raise("--main DIR is required")

    for row <- Contrast.run(paths(branch), %{main: main, branch: branch}), do: Mix.shell().info(Contrast.line(row))
  end

  @doc false
  def paths(branch) do
    {out, 0} = System.cmd("git", ["-C", branch, "diff", "--name-only", "origin/main", "HEAD"])
    String.split(out, "\n", trim: true)
  end
end
