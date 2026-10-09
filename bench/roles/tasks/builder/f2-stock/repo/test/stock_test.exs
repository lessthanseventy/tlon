Code.require_file("../lib/stock.ex", __DIR__)
ExUnit.start()

defmodule StockTest do
  use ExUnit.Case

  test "a reservation holds stock" do
    {:ok, s} = Stock.reserve(Stock.new(%{"mug" => 5}), "o1", "mug", 2)
    assert Stock.available(s, "mug") == 3
  end

  test "you cannot hold more than is available" do
    assert Stock.reserve(Stock.new(%{"mug" => 1}), "o1", "mug", 2) == {:error, :insufficient}
  end
end
