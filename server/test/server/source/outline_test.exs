defmodule Server.Source.OutlineTest do
  # The outline is what an agent reads before it edits: every module's defs with arity, kind,
  # the spec/doc it carries, and the lines it spans — as data, from the source alone.
  use ExUnit.Case, async: true

  alias Server.Source.Outline

  @src """
  defmodule Demo.A do
    @moduledoc "the demo"

    @doc "adds one"
    @spec inc(integer()) :: integer()
    def inc(n), do: n + 1

    def inc(n, m) do
      n + m
    end

    defp hidden(_x), do: :ok

    defmodule Inner do
      def z, do: 1
    end
  end
  """

  test "modules, defs with arity and kind, the doc's first line, line spans" do
    assert {:ok, [a]} = Outline.run(@src)
    assert a.module == "Demo.A"
    assert a.doc == "the demo"
    assert a.lines == {1, 17}

    assert [
             %{name: :inc, arity: 1, kind: :def, doc: "adds one", spec: "inc(integer()) :: integer()", lines: {6, 6}},
             %{name: :inc, arity: 2, kind: :def, doc: nil, spec: nil, lines: {8, 10}},
             %{name: :hidden, arity: 1, kind: :defp, lines: {12, 12}}
           ] = Enum.map(a.defs, &Map.take(&1, [:name, :arity, :kind, :doc, :spec, :lines]))

    assert [%{module: "Demo.A.Inner", defs: [%{name: :z, arity: 0}]}] = a.modules
  end

  test "an unparseable source is an error" do
    assert {:error, _} = Outline.run("defmodule (")
  end
end
