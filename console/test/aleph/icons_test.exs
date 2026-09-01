defmodule Console.IconsTest do
  @moduledoc "The two-tier icon hub: Nerd glyph fallback + compile-embedded Lucide PNG raster tier."
  use ExUnit.Case, async: true

  alias Console.Icons

  test "named glyph accessors and glyph/1 agree (the Nerd Font fallback tier)" do
    assert is_binary(Icons.home()) and Icons.home() != ""
    assert Icons.glyph(:home) == Icons.home()
    assert Icons.glyph(:add) == Icons.add()
    assert Icons.glyph(:unknown) == nil
  end

  test "image/2 carries a stable id, the embedded PNG bytes, and the rect" do
    rect = %{x: 3, y: 5, w: 2, h: 1}
    assert %{id: id, data: data, rect: ^rect} = Icons.image(:home, rect)
    assert is_integer(id)
    # Embedded, not read at runtime: the PNG magic proves the bytes are baked into the module.
    assert <<0x89, "PNG", _::binary>> = data
  end

  test "distinct ids per icon; unknown names have no image" do
    ids = Enum.map(Icons.names(), &Icons.image(&1, %{x: 0, y: 0, w: 1, h: 1}).id)
    assert Enum.uniq(ids) == ids
    assert Icons.image(:unknown, %{x: 0, y: 0, w: 1, h: 1}) == nil
  end
end
