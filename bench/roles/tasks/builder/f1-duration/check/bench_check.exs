Code.require_file("lib/duration.ex")
ExUnit.start()

defmodule BenchCheck do
  use ExUnit.Case

  test "valid durations" do
    assert Duration.parse("1h30m") == {:ok, 5400}
    assert Duration.parse("2d") == {:ok, 172_800}
    assert Duration.parse("0s") == {:ok, 0}
    assert Duration.parse("1d2h3m4s") == {:ok, 93_784}
    assert Duration.parse(" 45s ") == {:ok, 45}
    assert Duration.parse("90m") == {:ok, 5400}
  end

  test "order" do
    assert Duration.parse("30m1h") == {:error, :order}
    assert Duration.parse("1h1h") == {:error, :order}
  end

  test "empty" do
    assert Duration.parse("") == {:error, :empty}
    assert Duration.parse("   ") == {:error, :empty}
  end

  test "missing unit" do
    assert Duration.parse("90") == {:error, :missing_unit}
    assert Duration.parse("1h30") == {:error, :missing_unit}
  end

  test "bad unit" do
    assert Duration.parse("5w") == {:error, :bad_unit}
    assert Duration.parse("1H") == {:error, :bad_unit}
  end

  test "malformed" do
    for s <- ["h", "1 h", "-1h", "1.5h"], do: assert(Duration.parse(s) == {:error, :malformed}, s)
  end
end
