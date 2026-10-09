Code.require_file("lib/stock.ex")
ExUnit.start()

defmodule BenchCheck do
  use ExUnit.Case

  defp store do
    {:ok, s} = Stock.reserve(Stock.new(%{"mug" => 5, "cup" => 4}), "o1", "mug", 2)
    {:ok, s} = Stock.reserve(s, "o2", "mug", 1)
    {:ok, s} = Stock.reserve(s, "o3", "cup", 3)
    s
  end

  test "cancelling an order gives its hold back, and only its hold" do
    s = Stock.release(store(), "o1")
    assert Stock.available(s, "mug") == 4
    assert Stock.available(s, "cup") == 1
  end

  test "cancelling twice or an unknown order changes nothing" do
    s = Stock.release(store(), "o1")
    assert Stock.release(s, "o1") == s
    assert Stock.release(s, "nope") == s
  end

  test "shipping takes the items off the shelf once" do
    s = Stock.ship(store(), "o1")
    assert s.on_hand["mug"] == 3
    assert Stock.available(s, "mug") == 2
  end

  test "a shipped order cannot ship again or be cancelled back" do
    s = Stock.ship(store(), "o1")
    assert Stock.ship(s, "o1") == s
    assert Stock.available(Stock.release(s, "o1"), "mug") == 2
  end

  test "the original behaviour holds" do
    assert Stock.available(store(), "mug") == 2
    assert Stock.reserve(store(), "o4", "cup", 2) == {:error, :insufficient}
  end
end
