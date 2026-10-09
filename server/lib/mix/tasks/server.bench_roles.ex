defmodule Mix.Tasks.Server.BenchRoles do
  @shortdoc "Run the per-role bench — --suite canary|full [--role R]… [--model provider/model[:effort]]"
  @moduledoc """
  #{@shortdoc}.

  Each role's frozen tasks (`bench/roles/tasks/`) through the harness and model a coworker of it
  is routed to — or `--model`, to compare a role on another model without retargeting anything —
  graded, appended to `bench/roles/results/<date>.json`, and `bench/roles/README.md` regenerated
  (`Server.Bench.Roles.Runner`). Every role when no `--role` is given. It spends real model quota
  and starts no Repo: it reads and writes no database.
  """
  use Mix.Task
  use Boundary, classify_to: Server

  alias Server.Bench.Roles

  @impl Mix.Task
  def run(argv) do
    {opts, _rest} = OptionParser.parse!(argv, strict: [suite: :string, role: :keep, model: :string])
    suite = suite!(opts[:suite] || "canary")
    roles = roles!(Keyword.get_values(opts, :role))
    model = opts[:model] && model!(opts[:model])

    Mix.Task.run("app.config")
    Logger.configure(level: :warning)

    for r <- Roles.Runner.run(suite, roles, model: model) do
      tiers = Enum.map_join(r.tiers, " ", fn {tier, t} -> "#{tier} #{t.passed}/#{t.total}" end)
      Mix.shell().info("#{r.role} #{r.model}: #{tiers} · #{r.wall_s}s · #{r.usage.input}/#{r.usage.output} tokens")
    end
  end

  defp suite!(suite) when suite in ~w(canary full), do: suite
  defp suite!(suite), do: Mix.raise("--suite is canary or full, got #{inspect(suite)}")

  defp roles!([]), do: roles_sorted()

  defp roles!(roles) do
    case roles -- roles_sorted() do
      [] -> roles
      unknown -> Mix.raise("unknown role(s) #{Enum.join(unknown, ", ")}; roles: #{Enum.join(roles_sorted(), ", ")}")
    end
  end

  defp model!(spec) do
    case Roles.parse_model(spec) do
      {:ok, m} -> m
      {:error, why} -> Mix.raise(why)
    end
  end

  defp roles_sorted, do: Roles.roles() |> Map.keys() |> Enum.sort()
end
