defmodule Server.MigrationVersionsTest do
  use ExUnit.Case, async: true

  @migrations Path.expand("../../priv/repo/migrations/*.exs", __DIR__)

  # Round or hand-sequenced versions that were already on main; no new one joins them.
  @grandfathered ~w(
    20260918000000
    20260918010000
    20260918120000
    20260925100000
    20260925140000
    20260925150000
    20260930000000
    20260930010000
    20260930020000
    20261005000000
    20261006000000
    20261007000000
    20261008060000
    20261008070000
    20261008090000
    20261008100000
    20261008110000
    20261008120000
    20261008130000
    20261008140000
    20261008150000
    20261008160000
    20261009000000
    20261009020000
    20261009040000
    20261009060000
    20261009080000
    20261009100000
    20261009200000
    20261009220000
    20261009230000
    20261010020000
    20261010040000
    20261010100000
    20261012190000
    20261013160000
    20261017120000
    20261017150000
    20261019180000
    20261020050000
    20261020180000
    20261021230000
    20261022010000
    20261022020000
    20261022030000
    20261026060000
    20261026150000
    20261026160000
    20261026170000
    20261027080000
    20261027120000
    20261031120000
    20261108120000
    20261109120000
    20261109130000
    20261117150000
    20261117160000
    20261117170000
    20261117180000
    20261118090000
    20261118120000
    20261118150000
    20261119090000
    20261119120000
    20261119130000
    20261120090000
    20261120120000
    20261121090000
    20261121230000
    20261122020000
  )

  @hint "generate migrations with `mix ecto.gen.migration <name>` (the current UTC second); " <>
          "never write or round a version by hand, and after a rebase rename yours to a fresh timestamp if main has the same version"

  defp versions do
    for path <- Path.wildcard(@migrations), do: path |> Path.basename() |> String.split("_", parts: 2) |> hd()
  end

  test "migration versions are unique" do
    dupes = versions() -- Enum.uniq(versions())
    assert dupes == [], "duplicate migration versions #{inspect(Enum.uniq(dupes))}: #{@hint}"
  end

  test "no migration version is a round hour or a hand sequence" do
    hand = for v <- versions(), v not in @grandfathered, String.match?(v, ~r/(0000|00000\d)$/), do: v
    assert hand == [], "hand-picked migration versions #{inspect(hand)}: #{@hint}"
  end
end
