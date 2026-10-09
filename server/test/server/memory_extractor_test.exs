defmodule Server.MemoryExtractorTest do
  use ExUnit.Case, async: true

  alias Server.Memory.Extractor.Claude

  defp parse(facts), do: Claude.parse(Jason.encode!(%{facts: facts}))

  test "placeholder, punctuation-only and too-short facts are refused" do
    junk = for t <- ["...", "…", "  ", "", "?!", "- . -", "ok"], do: %{kind: "learned", text: t}

    real = [
      %{kind: "decision", text: "Ship the memory pass behind a flag"},
      %{kind: "constraint", text: "Use pnpm"}
    ]

    assert {:ok, [%{text: "Ship the memory pass behind a flag"}, %{text: "Use pnpm"}]} =
             parse(junk ++ real)
  end
end
