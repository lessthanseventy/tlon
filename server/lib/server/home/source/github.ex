defmodule Server.Home.Source.GitHub do
  @moduledoc """
  What GitHub suggests, through the `gh` the machine is already signed in with
  (`:home_gh`, a function of the argument list answering `{:ok, stdout}` or `{:error, reason}`, is
  where a test stands in):

    * `gh search prs --review-requested=@me --state=open`: `todo` "Review: <title>", asked by the author;
    * `gh search prs --author=@me --state=open --review=changes_requested`: `todo` "Changes requested: <title>";
    * `gh search prs --author=@me --state=open --review=none`: `waiting` "Waiting on review: <title>",
      taken by itself (`auto/0`): it is a fact about what is owed, said as "Reviewed: <title>" once a
      review comes.

  Drafts are skipped, and so are the repos and owners in the `home_github_ignore` setting (a comma
  list of `owner/repo` or `owner`). A key is the PR's URL and its role, so a PR that moves from one
  role to another is a key gone and a key new. A key known to the proposals and no longer listed is
  resolved; any failed search resolves nothing.
  """
  @behaviour Server.Home.Source

  alias Server.Proposal

  @fields "number,title,url,author,repository,isDraft"

  @impl true
  def name, do: "github"

  @impl true
  def auto, do: ["waiting"]

  @impl true
  def fetch do
    ignored = ignored()

    with {:ok, asked} <- search(["--review-requested=@me"]),
         {:ok, changes} <- search(["--author=@me", "--review=changes_requested"]),
         {:ok, waiting} <- search(["--author=@me", "--review=none"]) do
      proposals =
        for {role, prs} <- [review: asked, changes: changes, waiting: waiting],
            pr <- prs,
            not pr["isDraft"] and not ignored?(pr, ignored),
            do: proposal(role, pr)

      keys = MapSet.new(proposals, & &1.key)
      {:ok, proposals, Enum.reject(Proposal.live_keys(name()), &MapSet.member?(keys, &1))}
    end
  end

  defp search(flags) do
    args = ["search", "prs", "--state=open", "--draft=false", "--limit", "100", "--json", @fields] ++ flags

    with {:ok, out} <- Application.get_env(:server, :home_gh, &gh/1).(args) do
      case JSON.decode(out) do
        {:ok, prs} when is_list(prs) -> {:ok, prs}
        _ -> {:error, "gh answered something that is not a list of pull requests"}
      end
    end
  end

  defp gh(args) do
    case Server.Cmd.run("gh", args, timeout: 60) do
      {out, 0} -> {:ok, out}
      {_out, code} -> {:error, "gh exited #{code}"}
    end
  end

  defp proposal(:review, pr) do
    %{
      key: pr["url"] <> ":review",
      text: "Review: " <> pr["title"],
      why: "#{where(pr)}, asked by #{get_in(pr, ["author", "login"])}",
      kind: "todo",
      url: pr["url"]
    }
  end

  defp proposal(:changes, pr) do
    %{
      key: pr["url"] <> ":changes",
      text: "Changes requested: " <> pr["title"],
      why: where(pr),
      kind: "todo",
      url: pr["url"]
    }
  end

  defp proposal(:waiting, pr) do
    %{
      key: pr["url"] <> ":waiting",
      text: "Waiting on review: " <> pr["title"],
      why: where(pr),
      kind: "waiting",
      who: "a reviewer",
      url: pr["url"],
      done_text: "Reviewed: " <> pr["title"]
    }
  end

  defp where(pr), do: "#{pr["repository"]["nameWithOwner"]}##{pr["number"]}"

  defp ignored do
    "home_github_ignore"
    |> Server.OperatorConfig.setting()
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
  end

  defp ignored?(pr, ignored) do
    repo = String.downcase(pr["repository"]["nameWithOwner"])
    Enum.any?(ignored, &(repo == &1 or String.starts_with?(repo, &1 <> "/")))
  end
end
