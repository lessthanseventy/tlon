defmodule Server.PartCheckTest do
  use ExUnit.Case, async: true

  alias Server.PartCheck

  @row "..yyyyyy...."
  defp good, do: %{"slot" => "head", "front" => %{"2" => @row}, "side" => %{"2" => @row}, "back" => %{"2" => @row}}

  test "a well-formed part passes and comes back keyed by atoms" do
    assert {:ok, %{slot: "head", front: %{"2" => @row}, side: %{"2" => @row}, back: %{"2" => @row}}} =
             PartCheck.validate(good())
  end

  test "neck and hand are allowed, eyes mouth and back are not" do
    for s <- ~w(neck hand), do: assert({:ok, _} = PartCheck.validate(%{good() | "slot" => s}))
    for s <- ~w(eyes mouth back nope), do: assert({:error, :slot} = PartCheck.validate(%{good() | "slot" => s}))
  end

  test "all three views must be present and non-empty" do
    for v <- ~w(front side back) do
      assert {:error, {_, :missing}} = PartCheck.validate(Map.delete(good(), v))
      assert {:error, {_, :missing}} = PartCheck.validate(%{good() | v => %{}})
    end
  end

  test "rows are exactly 12 wide" do
    assert {:error, {:front, {:row, "2"}}} = PartCheck.validate(%{good() | "front" => %{"2" => "..yy"}})
    assert {:error, {:front, {:row, "2"}}} = PartCheck.validate(%{good() | "front" => %{"2" => @row <> "."}})
  end

  test "row index is 0 to 17" do
    assert {:ok, _} = PartCheck.validate(%{good() | "front" => %{"17" => @row}})
    assert {:error, {:front, {:row, "18"}}} = PartCheck.validate(%{good() | "front" => %{"18" => @row}})
    assert {:error, {:front, {:row, "x"}}} = PartCheck.validate(%{good() | "front" => %{"x" => @row}})
  end

  test "only the gear colours are legal; the body colours are refused" do
    assert {:ok, _} = PartCheck.validate(%{good() | "front" => %{"2" => "._ycgewro..."}})

    for bad <- ~w(k f s p b h),
        do:
          assert(
            {:error, {:front, {:row, "2"}}} = PartCheck.validate(%{good() | "front" => %{"2" => "..#{bad}.........."}})
          )
  end

  test "garbage is a shape error, never a crash" do
    for junk <- [nil, [], "x", %{}, %{"slot" => "head", "front" => "no"}],
        do: assert({:error, _} = PartCheck.validate(junk))
  end
end
