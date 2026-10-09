Code.require_file("lib/pager.ex")
ExUnit.start()

defmodule BenchCheck do
  use ExUnit.Case

  @items Enum.to_list(1..25)

  test "page 1 starts at the first item" do
    assert Pager.page(@items, 1, 10) == Enum.to_list(1..10)
  end

  test "the last page holds the remainder, and past it is empty" do
    assert Pager.page(@items, 3, 10) == Enum.to_list(21..25)
    assert Pager.page(@items, 4, 10) == []
  end

  test "a partial last page counts" do
    assert Pager.count(@items, 10) == 3
    assert Pager.count(Enum.to_list(1..20), 10) == 2
    assert Pager.count([], 10) == 0
  end
end
