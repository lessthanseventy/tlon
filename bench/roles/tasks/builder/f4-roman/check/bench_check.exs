Code.require_file("lib/roman.ex")
ExUnit.start()

defmodule BenchCheck do
  use ExUnit.Case

  test "canonical numerals" do
    assert Roman.to_integer("I") == {:ok, 1}
    assert Roman.to_integer("XLII") == {:ok, 42}
    assert Roman.to_integer("MCMXCIV") == {:ok, 1994}
    assert Roman.to_integer("MMXXVI") == {:ok, 2026}
    assert Roman.to_integer("MMMCMXCIX") == {:ok, 3999}
    assert Roman.to_integer("CDXLIV") == {:ok, 444}
  end

  test "non-canonical forms are invalid" do
    for s <- ~w(IIII VV IC IIV XM MMMM IL VX), do: assert(Roman.to_integer(s) == {:error, :invalid}, s)
  end

  test "anything else is invalid" do
    for s <- ["", "xlii", "ABC", "X I"], do: assert(Roman.to_integer(s) == {:error, :invalid}, s)
  end

  test "the teammate's test file agrees with the spec" do
    src = File.read!("test/roman_test.exs")
    refute src =~ "1996"
  end
end
