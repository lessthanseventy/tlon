defmodule Server.Canvas.Paint do
  @moduledoc """
  Paint the canvas (`Server.Canvas`) onto the contribution graph: a fresh history of backdated empty
  commits, one batch per shaded day, with `canvas.txt` (today's grid, what tomorrow's Life step reads)
  and a README saying plainly what the repo is, force-pushed over the canvas repo. One `git
  fast-import` writes the whole history, so a year of thousands of commits is one process.

  Today's picture is the newest one a coworker posted on the workspace's `canvas` thread in the last
  day; with none, Life steps yesterday's canvas; a canvas Life has emptied or frozen is reseeded from
  the date. Each shade is scaled over the busiest real day on the graph (GitHub's daily totals, read
  with `gh`, less the canvas's own commits); when GitHub can't be read the result's `peak` is nil and
  the canvas paints a quiet graph's shades. Opts: `remote:`, `today:`, `author: {name, email}`,
  `picture:` (text, over the thread's), `peak:` (over GitHub's), `workspace_id:` (default 1).
  """
  import Ecto.Query

  alias Server.Canvas

  @remote "https://github.com/lessthanseventy/canvas.git"

  @readme """
  # canvas

  This repository draws on my GitHub contribution graph. Its commits are empty and backdated;
  each shaded day gets enough to outnumber my busiest real day, so a picture shows up over real
  work. It is art, not activity, and it inflates my contribution count accordingly.

  The picture comes from the coworkers in my office ([tlon](https://github.com/lessthanseventy/tlon)):
  one of them posts a 52 × 7 drawing on a thread, and a scheduled job repaints this history from it
  every morning. When nobody draws, the canvas plays Conway's Game of Life, one generation a day.

  `canvas.txt` is today's grid.
  """

  @doc "Paint today's canvas. `{:ok, %{source, commits, peak}}` | `{:error, why}`."
  def run(opts \\ []) do
    today = Keyword.get_lazy(opts, :today, fn -> Server.Schedules.local_date(DateTime.utc_now()) end)
    remote = Keyword.get(opts, :remote, Application.get_env(:server, :canvas_remote, @remote))
    author = Keyword.get_lazy(opts, :author, &author/0)

    {source, grid} = pick(opts, remote, today)
    peak = Keyword.get_lazy(opts, :peak, fn -> real_peak(remote) end)
    plan = Canvas.plan(grid, today, peak || 0)
    dir = Path.join(System.tmp_dir!(), "canvas-paint-#{System.unique_integer([:positive])}")

    try do
      with :ok <- build(dir, plan, grid, author, today),
           :ok <- push(dir, remote) do
        {:ok, %{source: source, commits: plan |> Map.values() |> Enum.sum(), peak: peak}}
      end
    after
      File.rm_rf(dir)
    end
  end

  defp pick(opts, remote, today) do
    case picture(opts) do
      {:ok, grid} ->
        {:picture, grid}

      :error ->
        prev = previous(remote)
        next = prev && Canvas.life(prev)
        if (next && next != prev) and next != Canvas.blank(), do: {:life, next}, else: {:seed, soup(today)}
    end
  end

  defp picture(opts) do
    case opts[:picture] do
      text when is_binary(text) -> Canvas.parse(text)
      nil -> posted(Keyword.get(opts, :workspace_id, 1))
    end
  end

  # the newest picture a coworker posted on the workspace's canvas thread in the last day
  defp posted(ws) do
    since = DateTime.add(DateTime.utc_now(), -86_400, :second)

    from(m in Server.Message,
      join: t in Server.Thread,
      on: t.id == m.thread_id,
      where: t.workspace_id == ^ws and t.title == "canvas" and m.author != "tlon" and m.created_at > ^since,
      order_by: [desc: m.id],
      select: m.body
    )
    |> Server.Repo.all()
    |> Enum.find_value(
      :error,
      &case Canvas.find_picture(&1) do
        {:ok, _} = ok -> ok
        _ -> nil
      end
    )
  end

  # yesterday's grid, read from the canvas repo's own canvas.txt
  defp previous(remote) do
    tmp = Path.join(System.tmp_dir!(), "canvas-prev-#{System.unique_integer([:positive])}")

    try do
      with {_, 0} <- System.cmd("git", ["clone", "-q", "--depth", "1", remote, tmp], stderr_to_stdout: true),
           {:ok, text} <- File.read(Path.join(tmp, "canvas.txt")),
           {:ok, grid} <- Canvas.parse(text) do
        grid
      else
        _ -> nil
      end
    after
      File.rm_rf(tmp)
    end
  end

  # nil when GitHub can't be read (no github.com remote, no gh, an error): the quiet-graph shades
  defp real_peak(remote) do
    with [_, login] <- Regex.run(~r{github\.com[/:]([^/]+)/}, remote),
         {:ok, totals} <- calendar(login) do
      Canvas.real_peak(totals, painted(remote))
    else
      _ -> nil
    end
  end

  defp calendar(login) do
    query =
      "query($login:String!){user(login:$login){contributionsCollection{contributionCalendar{weeks{contributionDays{date contributionCount}}}}}}"

    with {out, 0} <- System.cmd("gh", ["api", "graphql", "-f", "query=#{query}", "-F", "login=#{login}"]),
         {:ok, %{"data" => %{"user" => %{"contributionsCollection" => %{"contributionCalendar" => cal}}}}} <-
           Jason.decode(out) do
      {:ok,
       for(
         w <- cal["weeks"],
         d <- w["contributionDays"],
         into: %{},
         do: {Date.from_iso8601!(d["date"]), d["contributionCount"]}
       )}
    else
      _ -> :error
    end
  rescue
    ErlangError -> :error
  end

  # the canvas's own pixel commits per day, read from the history it pushed last
  defp painted(remote) do
    tmp = Path.join(System.tmp_dir!(), "canvas-painted-#{System.unique_integer([:positive])}")

    try do
      with {_, 0} <- System.cmd("git", ["clone", "-q", "--bare", remote, tmp], stderr_to_stdout: true),
           {out, 0} <- git(tmp, ["log", "--format=%ad", "--date=short", "--grep=^pixel$"]) do
        out |> String.split("\n", trim: true) |> Enum.frequencies_by(&Date.from_iso8601!/1)
      else
        _ -> %{}
      end
    after
      File.rm_rf(tmp)
    end
  end

  # a fresh random soup, the same for a given day
  defp soup(today) do
    :rand.seed(:exsss, {today.year, today.month, today.day})
    Map.new(Canvas.blank(), fn {cell, _} -> {cell, if(:rand.uniform() < 0.3, do: 4, else: 0)} end)
  end

  defp build(dir, plan, grid, {name, email}, today) do
    File.mkdir_p!(dir)

    with {_, 0} <- git(dir, ["init", "-q", "-b", "main"]),
         {_, 0} <- fast_import(dir, stream(plan, grid, "#{name} <#{email}>", today)) do
      :ok
    else
      {out, _} -> {:error, "building the canvas history failed: #{String.slice(out, 0, 300)}"}
    end
  end

  # every shaded day's commits at noon UTC, oldest first, then the files on today's commit
  defp stream(plan, grid, who, today) do
    commits =
      for {date, n} <- Enum.sort_by(plan, &elem(&1, 0), Date), i <- 1..n do
        at = date |> DateTime.new!(~T[12:00:00]) |> DateTime.add(i, :second) |> DateTime.to_unix()
        commit(who, at, "pixel", [])
      end

    at = today |> DateTime.new!(~T[23:00:00]) |> DateTime.to_unix()
    files = [{"README.md", @readme}, {"canvas.txt", Canvas.to_text(grid)}]
    Enum.join(commits ++ [commit(who, at, "canvas for #{today}", files)])
  end

  defp commit(who, at, msg, files) do
    ops = Enum.map_join(files, fn {path, text} -> "M 100644 inline #{path}\ndata #{byte_size(text)}\n#{text}\n" end)

    "commit refs/heads/main\nauthor #{who} #{at} +0000\ncommitter #{who} #{at} +0000\ndata #{byte_size(msg)}\n#{msg}\n#{ops}\n"
  end

  defp fast_import(dir, stream) do
    File.write!(Path.join(dir, ".git/canvas-import"), stream)
    System.cmd("sh", ["-c", "git fast-import --quiet < .git/canvas-import"], cd: dir, stderr_to_stdout: true)
  end

  defp push(dir, remote) do
    case git(dir, ["push", "-q", "--force", remote, "main:main"]) do
      {_, 0} -> :ok
      {out, _} -> {:error, "pushing the canvas failed: #{String.slice(out, 0, 300)}"}
    end
  end

  defp git(dir, args), do: System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)

  # the commits must carry an email GitHub ties to Andrew's account, or the graph never sees them
  defp author do
    root = Server.Profiles.tlon_root()
    name = root |> git(["config", "user.name"]) |> elem(0) |> String.trim()
    email = root |> git(["config", "user.email"]) |> elem(0) |> String.trim()
    {name, email}
  end
end
