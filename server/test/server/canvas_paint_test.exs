defmodule Server.Canvas.PaintTest do
  # The paint: a fresh history of backdated empty commits (the picture's plan), canvas.txt and an
  # honest README on top, force-pushed over the canvas repo. A local bare repo stands in for GitHub.
  use ExUnit.Case, async: false

  alias Server.Canvas
  alias Server.Canvas.Paint

  @today ~D[2026-10-08]

  setup do
    Server.TestDB.clean!()
    dir = Path.join(System.tmp_dir!(), "canvas-#{System.unique_integer([:positive])}")
    remote = Path.join(dir, "canvas.git")
    File.mkdir_p!(remote)
    {_, 0} = System.cmd("git", ["init", "-q", "--bare", "-b", "main", remote])
    on_exit(fn -> File.rm_rf!(dir) end)
    %{remote: remote, opts: [remote: remote, today: @today, author: {"Andrew", "a@example.com"}]}
  end

  defp git(remote, args), do: remote |> then(&System.cmd("git", ["--git-dir", &1 | args])) |> elem(0)

  test "a picture becomes its plan's commits, each on its day, under the README and canvas.txt", %{
    remote: remote,
    opts: opts
  } do
    picture = Enum.join(["#" <> String.duplicate(".", 51) | List.duplicate(String.duplicate(".", 52), 6)], "\n")
    assert {:ok, %{source: :picture, commits: n}} = Paint.run(Keyword.put(opts, :picture, picture))
    {:ok, grid} = Canvas.parse(picture)
    assert n == grid |> Canvas.plan(@today) |> Map.values() |> Enum.sum()

    dates = remote |> git(["log", "--format=%ad", "--date=short", "main"]) |> String.split("\n", trim: true)
    assert length(dates) == n + 1
    assert Enum.count(dates, &(&1 == Date.to_iso8601(Canvas.date_at(0, 0, @today)))) == Canvas.commits_for(4)
    assert git(remote, ["show", "main:canvas.txt"]) == Canvas.to_text(grid)
    assert git(remote, ["show", "main:README.md"]) =~ "contribution graph"
    assert git(remote, ["log", "-1", "--format=%ae", "main"]) =~ "a@example.com"
  end

  test "a peak paints each shade over it: the darkest day outnumbers the busiest real one", %{
    remote: remote,
    opts: opts
  } do
    picture = Enum.join(["#" <> String.duplicate(".", 51) | List.duplicate(String.duplicate(".", 52), 6)], "\n")
    assert {:ok, %{peak: 100}} = opts |> Keyword.put(:picture, picture) |> Keyword.put(:peak, 100) |> Paint.run()

    dates = remote |> git(["log", "--format=%ad", "--date=short", "main"]) |> String.split("\n", trim: true)
    assert Enum.count(dates, &(&1 == Date.to_iso8601(Canvas.date_at(0, 0, @today)))) == 101
  end

  test "with no picture it plays Life from yesterday's canvas, and repaints the whole history", %{
    remote: remote,
    opts: opts
  } do
    blinker =
      for r <- 0..6,
          do:
            if(r in 2..4,
              do: String.duplicate(".", 10) <> "#" <> String.duplicate(".", 41),
              else: String.duplicate(".", 52)
            )

    {:ok, _} = Paint.run(Keyword.put(opts, :picture, Enum.join(blinker, "\n")))
    assert {:ok, %{source: :life}} = Paint.run(opts)

    {:ok, before} = Canvas.parse(Enum.join(blinker, "\n"))
    assert git(remote, ["show", "main:canvas.txt"]) == Canvas.to_text(Canvas.life(before))
  end
end
