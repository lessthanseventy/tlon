defmodule Server.Canvas do
  @moduledoc """
  Andrew's GitHub contribution graph as a canvas: 52 week columns × 7 day rows (Sunday on top), the
  last column being this week. A picture is seven lines of `.` (blank) and `1`–`4` or `#` (shade 1–4,
  `#` the darkest); a shaded day is painted with backdated empty commits, more for a darker shade,
  scaled over the busiest real day so the picture reads over real work (`Server.Canvas.Paint` does
  the git). With no new picture the canvas plays Conway's Life, one
  generation a day, on a torus.

  Pure: grids are maps of `{col, row} => shade`, every cell present.
  """

  @width 52
  @height 7
  @quiet_top 12

  @type grid :: %{{non_neg_integer(), non_neg_integer()} => 0..4}

  @doc "The date of cell `{col, row}` on the graph that ends with `today`'s week."
  @spec date_at(non_neg_integer(), non_neg_integer(), Date.t()) :: Date.t()
  def date_at(col, row, today) do
    this_sunday = Date.add(today, 1 - Date.day_of_week(today, :sunday))
    Date.add(this_sunday, 7 * (col - (@width - 1)) + row)
  end

  @doc "Seven lines of shades (each padded to #{@width} columns) as a grid; anything else is `:error`."
  @spec parse(String.t()) :: {:ok, grid()} | :error
  def parse(text) do
    lines = text |> String.split("\n") |> Enum.map(&String.trim_trailing/1) |> Enum.reject(&(&1 == ""))

    with true <- length(lines) == @height,
         true <- Enum.all?(lines, &(String.length(&1) <= @width and &1 =~ ~r/\A[.#1-4 ]+\z/)) do
      grid =
        for {line, row} <- Enum.with_index(lines),
            {ch, col} <- line |> String.pad_trailing(@width, ".") |> String.graphemes() |> Enum.with_index(),
            into: %{},
            do: {{col, row}, shade_of(ch)}

      {:ok, grid}
    else
      _ -> :error
    end
  end

  @doc "The first picture in `body`: a fenced block that parses, else the whole body."
  @spec find_picture(String.t()) :: {:ok, grid()} | :error
  def find_picture(body) do
    blocks = for [_, b] <- Regex.scan(~r/```[a-z]*\n(.*?)```/s, body), do: b

    Enum.find_value(
      blocks ++ [body],
      :error,
      &case parse(&1) do
        {:ok, _} = ok -> ok
        _ -> nil
      end
    )
  end

  @doc "A cell's shade, 0 when blank."
  def shade(grid, col, row), do: Map.get(grid, {col, row}, 0)

  @doc "One generation of Life (B3/S23) on the #{@width} × #{@height} torus; the living are shade 4."
  @spec life(grid()) :: grid()
  def life(grid) do
    for col <- 0..(@width - 1), row <- 0..(@height - 1), into: %{} do
      alive = shade(grid, col, row) > 0
      n = Enum.count(neighbours(col, row), fn {c, r} -> shade(grid, c, r) > 0 end)
      {{col, row}, if(n == 3 or (alive and n == 2), do: 4, else: 0)}
    end
  end

  @doc "A blank grid."
  def blank, do: for(col <- 0..(@width - 1), row <- 0..(@height - 1), into: %{}, do: {{col, row}, 0})

  @doc "Every shaded day up to `today` with how many commits paint it, over a busiest real day of `peak`."
  @spec plan(grid(), Date.t(), non_neg_integer()) :: %{Date.t() => pos_integer()}
  def plan(grid, today, peak \\ 0) do
    for {{col, row}, s} <- grid,
        s > 0,
        date = date_at(col, row, today),
        Date.compare(date, today) != :gt,
        into: %{},
        do: {date, commits_for(s, peak)}
  end

  @doc """
  Commits for a shade on a graph whose busiest real day is `peak`. GitHub shades a day by its quarter
  of the busiest day, so shade 4 is one more than `peak` (it becomes the busiest day) and shades 1–3
  sit mid-quarter beneath it. A quiet graph tops out at #{@quiet_top}.
  """
  def commits_for(shade, peak \\ 0) when shade in 1..4 do
    top = max(peak + 1, @quiet_top)
    if shade == 4, do: top, else: ceil(top * (2 * shade - 1) / 8)
  end

  @doc "The busiest real day: each day's total (`date => count`) less the canvas's own commits on it."
  @spec real_peak(%{Date.t() => non_neg_integer()}, %{Date.t() => non_neg_integer()}) :: non_neg_integer()
  def real_peak(totals, canvas) do
    totals |> Enum.map(fn {date, n} -> n - Map.get(canvas, date, 0) end) |> Enum.max(fn -> 0 end) |> max(0)
  end

  @doc "The grid as the picture text it parses from."
  @spec to_text(grid()) :: String.t()
  def to_text(grid) do
    Enum.map_join(0..(@height - 1), "\n", fn row ->
      Enum.map_join(0..(@width - 1), fn col -> char_of(shade(grid, col, row)) end)
    end)
  end

  defp neighbours(col, row) do
    for dc <- -1..1,
        dr <- -1..1,
        {dc, dr} != {0, 0},
        do: {Integer.mod(col + dc, @width), Integer.mod(row + dr, @height)}
  end

  defp shade_of("#"), do: 4
  defp shade_of(d) when d in ~w(1 2 3 4), do: String.to_integer(d)
  defp shade_of(_), do: 0

  defp char_of(0), do: "."
  defp char_of(4), do: "#"
  defp char_of(s), do: Integer.to_string(s)
end
