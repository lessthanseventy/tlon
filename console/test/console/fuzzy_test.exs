defmodule Console.FuzzyTest do
  use ExUnit.Case, async: true

  alias Console.Fuzzy

  describe "match/2" do
    test "an empty query matches everything at 0" do
      assert Fuzzy.match("anything", "") == 0
    end

    test "a subsequence matches, a non-subsequence does not" do
      assert Fuzzy.match("cockpit slice", "cps") != nil
      assert Fuzzy.match("cockpit slice", "spc") == nil
    end

    test "is case-insensitive both ways" do
      assert Fuzzy.match("Cockpit", "ck") != nil
      assert Fuzzy.match("cockpit", "CK") != nil
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

  describe "filter/3" do
    test "an empty query keeps every entry in the order handed in" do
      assert Fuzzy.filter(~w(gamma alpha beta), "") == ~w(gamma alpha beta)
    end

    test "drops non-matches and ranks the rest" do
      assert Fuzzy.filter(~w(cockpit slice ticket), "ck") == ~w(cockpit ticket)
    end

    test "ties break on the shorter subject" do
      # identical prefix match, so identical score — the shorter one is the better answer
      assert Fuzzy.filter(["cab-extra", "cab"], "cab") == ["cab", "cab-extra"]
    end

    test "reads the subject through the accessor" do
      entries = [%{text: "cockpit"}, %{text: "notes"}]
      assert Fuzzy.filter(entries, "ck", & &1.text) == [%{text: "cockpit"}]
    end
  end
end
