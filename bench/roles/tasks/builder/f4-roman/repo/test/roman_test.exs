Code.require_file("../lib/roman.ex", __DIR__)
ExUnit.start()

defmodule RomanTest do
  use ExUnit.Case

  test "simple numerals" do
    assert Roman.to_integer("III") == {:ok, 3}
    assert Roman.to_integer("XLII") == {:ok, 42}
  end

  test "subtractive pairs" do
    assert Roman.to_integer("IX") == {:ok, 9}
    assert Roman.to_integer("MCMXCIV") == {:ok, 1996}
  end

  test "not a numeral" do
    assert Roman.to_integer("ABC") == {:error, :invalid}
  end
end
