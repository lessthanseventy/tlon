Code.require_file("lib/slug.ex")
ExUnit.start()

defmodule BenchCheck do
  use ExUnit.Case

  test "the examples" do
    assert Slug.slugify("  Hello, World!  ") == "hello-world"
    assert Slug.slugify("Orbis Tertius -- vol. 11") == "orbis-tertius-vol-11"
    assert Slug.slugify("!!!") == ""
  end

  test "accents fold" do
    assert Slug.slugify("Café Tlön") == "cafe-tlon"
    assert Slug.slugify("Uqbar ÉTÉ") == "uqbar-ete"
  end

  test "runs collapse, ends trim" do
    assert Slug.slugify("--a__b  c--") == "a-b-c"
    assert Slug.slugify("ABC123") == "abc123"
  end
end
