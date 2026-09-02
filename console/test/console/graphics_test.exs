defmodule Console.GraphicsTest do
  use ExUnit.Case, async: true

  alias Console.Graphics

  test "transmit/2 chunks base64 PNG into APC sequences, m=1 until the last" do
    png = :crypto.strong_rand_bytes(5000)
    seqs = Graphics.transmit(7, png)

    assert length(seqs) > 1
    assert List.first(seqs) =~ "\e_G"
    assert List.first(seqs) =~ "i=7"
    assert List.first(seqs) =~ "m=1"
    refute List.last(seqs) =~ "m=1"
    assert Enum.all?(seqs, &String.ends_with?(&1, "\e\\"))
  end

  test "transmit/2 with a single-chunk payload emits exactly one APC with no m param" do
    seqs = Graphics.transmit(3, <<1, 2, 3>>)

    assert [only] = seqs
    assert only =~ "\e_G"
    assert only =~ "i=3"
    refute only =~ "m="
    assert String.ends_with?(only, "\e\\")
  end

  test "place/2 saves the cursor, moves to the cell, places, restores" do
    io = 7 |> Graphics.place(%{x: 4, y: 2, w: 10, h: 5}) |> IO.iodata_to_binary()
    assert io =~ "\e[3;5H"
    assert io =~ "a=p"
    assert io =~ "i=7"
    assert io =~ "c=10,r=5"
  end

  test "delete/1 deletes by id" do
    assert Graphics.delete(7) =~ "a=d,d=i,i=7"
  end

  test "placeholder/2 is a dim run" do
    assert Graphics.placeholder(10, 4) == [{"[image 10x4]", :dim}]
  end

  test "sync/2 transmits once, places every frame, deletes the vanished" do
    wanted = [%{id: 1, data: <<1, 2, 3>>, rect: %{x: 0, y: 0, w: 4, h: 2}}]

    {io1, cache1} = Graphics.sync(wanted, MapSet.new())
    assert IO.iodata_to_binary(io1) =~ "a=t"
    assert MapSet.member?(cache1, 1)

    {io2, _cache2} = Graphics.sync(wanted, cache1)
    refute IO.iodata_to_binary(io2) =~ "a=t"
    assert IO.iodata_to_binary(io2) =~ "a=p"

    {io3, cache3} = Graphics.sync([], cache1)
    assert IO.iodata_to_binary(io3) =~ "a=d"
    refute MapSet.member?(cache3, 1)
  end
end
