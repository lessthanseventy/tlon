defmodule Server.Source.RenameTest do
  # AST-aware renames (Sourceror): the identifier changes wherever it is an identifier — def/defp
  # heads, calls, captures, variables — and, on request, the atom and keyword key too; a string or
  # a comment mentioning the name is left alone. Comments and layout survive (2026-09-08: text
  # edits kept dying to a `mix format` reflow).
  use ExUnit.Case, async: true

  alias Server.Source.Rename

  @src """
  defmodule Demo do
    # the author_workspaces list — a comment stays
    @doc "author_workspaces in a string stays"
    def author_workspaces(state), do: Map.get(state, :author_workspaces, [])

    defp count(state), do: length(author_workspaces(state))

    def ring(state), do: Enum.map(author_workspaces(state), & &1.id) |> Kernel.++([&author_workspaces/1])

    def keys, do: %{author_workspaces: 1, other: "author_workspaces"}
  end
  """

  test "renames def heads, calls and captures; leaves strings and comments" do
    out = Rename.run(@src, "author_workspaces", "live_workspaces")
    assert out =~ "def live_workspaces(state), do: Map.get(state, :author_workspaces, [])"
    assert out =~ "length(live_workspaces(state))"
    assert out =~ "&live_workspaces/1"
    assert out =~ "# the author_workspaces list — a comment stays"
    assert out =~ ~s(@doc "author_workspaces in a string stays")
    assert out =~ ~s("author_workspaces"})
    # the atom and the keyword key are untouched without the flag
    assert out =~ ":author_workspaces, []"
    assert out =~ "%{author_workspaces: 1"
  end

  test "with atoms: true the atom and the keyword key follow" do
    out = Rename.run(@src, "author_workspaces", "live_workspaces", atoms: true)
    assert out =~ "Map.get(state, :live_workspaces, [])"
    assert out =~ "%{live_workspaces: 1"
    assert out =~ ~s(other: "author_workspaces")
  end

  test "a source with nothing to rename comes back byte-identical" do
    assert Rename.run(@src, "nothing_here", "x") == @src
  end

  test "an unparseable source is an error, never a partial write" do
    assert {:error, _} = Rename.run("def (", "a", "b")
  end

  # The patch discipline: only the renamed bytes move. Odd layout, comments, blank runs — all kept.
  test "everything but the identifier is byte-for-byte the same" do
    src =
      "defmodule Odd do\n\n\n  def   author_workspaces( s ),   do:   s   # keep\n\n  def two, do: author_workspaces(1)\nend\n"

    out = Rename.run(src, "author_workspaces", "live_workspaces")

    assert out ==
             "defmodule Odd do\n\n\n  def   live_workspaces( s ),   do:   s   # keep\n\n  def two, do: live_workspaces(1)\nend\n"
  end
end
