defmodule Server.SoulCallersTest do
  # A soul shapes talk and tone, never a work decision. The structural half of that is that
  # nothing but banter and the brief builder can read one.
  use ExUnit.Case, async: true

  @lib Path.expand("../../lib", __DIR__)
  @allowed ~w(server/soul.ex server/office/banter.ex server/profiles.ex)

  test "Server.Soul.read/voice/tone are called only from banter.ex and profiles.ex" do
    offenders =
      @lib
      |> Path.join("**/*.ex")
      |> Path.wildcard()
      |> Enum.map(&Path.relative_to(&1, @lib))
      |> Enum.reject(&(&1 in @allowed))
      |> Enum.filter(fn rel -> File.read!(Path.join(@lib, rel)) =~ ~r/\bSoul\.(read|voice|tone)\b/ end)

    assert offenders == [],
           "these read a soul; a soul must not reach a work decision: #{inspect(offenders)}. " <>
             "If one is a new voice surface, add it to @allowed in this test and to the spec."
  end
end
