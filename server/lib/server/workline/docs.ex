defmodule Server.Workline.Docs do
  @moduledoc """
  A workline's docs (`work/<slug>/*.md`: intent, spec, plan, review, anything its leads add), for
  the operator to read — served at `GET /api/threads/:id/docs` and `…/docs/<name>`. Read from the
  workline's branch, where its leads commit them, else from the main checkout. `"current"` names
  the doc the stage is about: the one it owes, or at build and verify the plan being worked to.
  """

  alias Server.Workline.Artifacts

  @current %{
    "intent" => "intent.md",
    "spec" => "spec.md",
    "plan" => "plan.md",
    "build" => "plan.md",
    "verify" => "plan.md",
    "review" => "review.md",
    "merged" => "review.md"
  }

  @doc "The workline's doc names, from its branch and the main checkout."
  @spec list(Server.Thread.t()) :: [String.t()]
  def list(%{slug: slug} = thread) when is_binary(slug) do
    dir = "work/#{slug}/"

    [
      git(thread, ["ls-tree", "--name-only", "refs/heads/work/#{slug}", "--", dir]),
      git(thread, ["ls-files", "--", dir])
    ]
    |> Enum.flat_map(fn
      {out, 0} -> String.split(out, "\n", trim: true)
      _ -> []
    end)
    |> Enum.map(&Path.basename/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def list(_thread), do: []

  @doc "One doc's text by name (or `\"current\"`), from the branch first. `{:ok, text}` | `{:error, why}`."
  @spec read(Server.Thread.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def read(%{stage: stage} = thread, "current"), do: read(thread, Map.get(@current, stage, "intent.md"))

  def read(%{slug: slug} = thread, name) when is_binary(slug) do
    path = "work/#{slug}/#{name}"

    if name in list(thread),
      do:
        Enum.find_value(
          ["refs/heads/work/#{slug}:#{path}", "HEAD:#{path}"],
          {:error, "#{path} is not committed"},
          &show(thread, &1)
        ),
      else: {:error, "no doc #{name} in work/#{slug}/"}
  end

  def read(_thread, _name), do: {:error, "not a workline"}

  defp show(thread, ref) do
    case git(thread, ["show", ref]) do
      {text, 0} -> {:ok, text}
      _ -> nil
    end
  end

  defp git(thread, args), do: System.cmd("git", ["-C", Artifacts.Git.root(thread) | args], stderr_to_stdout: true)
end
