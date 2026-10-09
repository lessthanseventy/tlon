Code.require_file("../lib/pager.ex", __DIR__)
ExUnit.start()

defmodule PagerTest do
  use ExUnit.Case

  test "an empty list has no pages" do
    assert Pager.count([], 10) == 0
  end
end
