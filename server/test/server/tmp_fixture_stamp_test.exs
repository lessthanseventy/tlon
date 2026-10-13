defmodule Server.TmpFixtureStampTest do
  use ExUnit.Case, async: true

  # Two gates at once are two BEAMs whose unique_integer sequences restart, so a /tmp fixture named
  # only by unique_integer can collide and one run's rm_rf wipes the other's repo (ticket #329).
  # The tmp_dir! may sit a few lines below the unique_integer that names it (arbiter_tmux_test), so
  # a window after the line counts; a one-line match alone missed that site.
  test "no test names a tmp fixture by unique_integer alone — stamp it with System.pid()" do
    self_path = Path.expand(__ENV__.file)

    offenders =
      "../**/*_test.exs"
      |> Path.expand(__DIR__)
      |> Path.wildcard()
      |> Enum.reject(&(&1 == self_path))
      |> Enum.flat_map(fn file ->
        lines = file |> File.read!() |> String.split("\n")

        lines
        |> Enum.with_index()
        |> Enum.filter(fn {line, i} ->
          unstamped = line =~ "System.unique_integer" and not (line =~ "System.pid()")
          nearby_tmp = Enum.any?(Enum.slice(lines, i, 5), &(&1 =~ "System.tmp_dir!()"))
          unstamped and nearby_tmp
        end)
        |> Enum.map(fn {_, i} -> "#{Path.relative_to_cwd(file)}:#{i + 1}" end)
      end)

    assert offenders == []
  end
end
