defmodule Console.FuzzyTest do
  use ExUnit.Case, async: true

  alias Console.Fuzzy

  doctest Console.Fuzzy

  describe "match/2" do
    test "a subsequence matches, a non-subsequence does not" do
      assert Fuzzy.match("cockpit slice", "cps")
      assert Fuzzy.match("cockpit slice", "spc") == nil
    end

    test "is case-insensitive both ways" do
      assert Fuzzy.match("Cockpit", "ck")
      assert Fuzzy.match("cockpit", "CK")
    end

    test "a word-start run outranks the same letters scattered mid-word" do
      # "fc" as the initials of two words beats "fc" buried inside one
      initials = Fuzzy.match("ficciones cockpit", "fc")
      buried = Fuzzy.match("affected", "fc")
      assert initials > buried
    end

    test "an adjacent run outranks a scattered match in the same subject" do
      assert Fuzzy.match("slicer", "sli") > Fuzzy.match("slicer", "sir")
    end

    test "separators start a word — the switcher's path shape" do
      assert Fuzzy.match("ficciones · #general · cockpit", "fgc") > Fuzzy.match("ficciones · #general · cockpit", "fnp")
    end
  end
end
