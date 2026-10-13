defmodule Server.TmpFixtureStampTest do
  use ExUnit.Case, async: true

  # Two gates at once are two BEAMs whose unique_integer sequences restart, so a /tmp fixture named
  # only by unique_integer can collide and one run's rm_rf wipes the other's repo (ticket #329).
  test "no test names a tmp fixture by unique_integer alone — stamp it with System.pid()" do
    self_path = Path.expand(__ENV__.file)

    offenders =
      Path.wildcard(Path.expand("../**/*_test.exs", __DIR__))
      |> Enum.reject(&(&1 == self_path))
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} ->
          line =~ "System.tmp_dir!()" and line =~ "System.unique_integer" and
            not (line =~ "System.pid()")
        end)
        |> Enum.map(fn {_, n} -> "#{Path.relative_to_cwd(file)}:#{n}" end)
      end)

    assert offenders == []
  end
end
