defmodule Server.Source.ClauseTest do
  # The clause verbs — what replaces the grep/sed dance: address a clause by `name/arity` and a
  # head pattern (its args, as written), then replace its body, delete it, or insert a new clause
  # after it. Patches, not reprints: everything else in the file is byte-identical.
  use ExUnit.Case, async: true

  alias Server.Source.Clause

  @src """
  defmodule Demo do
    # first
    def go(:a), do: 1

    # second
    def go(:b) do
      2
    end

    def go(other), do: other
  end
  """

  test "replace_body swaps one clause's body, one-liner or block, leaving the rest" do
    out = Clause.replace_body(@src, "go/1", ":b", "20")
    assert out =~ "def go(:b), do: 20"
    refute out =~ "\n    2\n"
    assert out =~ "# first\n  def go(:a), do: 1"
    assert out =~ "def go(other), do: other"
  end

  test "delete removes the clause (and the comment glued above it), nothing else" do
    out = Clause.delete(@src, "go/1", ":a")
    refute out =~ "go(:a)"
    refute out =~ "# first"
    assert out =~ "# second\n  def go(:b) do"
    assert out =~ "def go(other), do: other"
  end

  test "insert_after adds a clause right after the addressed one" do
    out = Clause.insert_after(@src, "go/1", ":a", "def go(:c), do: 3")
    assert out =~ "def go(:a), do: 1\n  def go(:c), do: 3\n"
  end

  test "an unknown clause is an error naming the candidates" do
    assert {:error, msg} = Clause.replace_body(@src, "go/1", ":zzz", "1")
    assert msg =~ "go/1" and msg =~ ":a"
    assert {:error, _} = Clause.delete(@src, "nope/0", "", [])
  end

  test "a guard is part of the head" do
    src = "defmodule G do\n  def f(x) when is_integer(x), do: x\n  def f(x), do: 0\nend\n"
    assert Clause.replace_body(src, "f/1", "x when is_integer(x)", "x * 2") =~ "def f(x) when is_integer(x), do: x * 2"
    assert Clause.delete(src, "f/1", "x") == "defmodule G do\n  def f(x) when is_integer(x), do: x\nend\n"
  end
end
