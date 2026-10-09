Code.require_file("lib/report.ex")
ExUnit.start()

defmodule BenchCheck do
  use ExUnit.Case

  @rows [%{name: "gate", runs: 7, ratio: 0.857}, %{name: "smoke", runs: 3, ratio: 1}]

  test "the text table is unchanged" do
    assert Report.render(@rows) ==
             "check         runs   pass\n" <>
               "gate             7   0.86\n" <>
               "smoke            3   1.00\n" <>
               "total           10\n"

    assert Report.render([]) == "check         runs   pass\ntotal            0\n"
  end

  test "csv" do
    assert Report.render(@rows, :csv) == "check,runs,pass\ngate,7,0.86\nsmoke,3,1.00\n"
    assert Report.render([], :csv) == "check,runs,pass\n"
  end

  test "csv quotes names with commas or quotes" do
    rows = [%{name: ~s(say "hi", ok), runs: 1, ratio: 0.5}, %{name: "a,b", runs: 2, ratio: 0}]
    assert Report.render(rows, :csv) == ~s(check,runs,pass\n"say ""hi"", ok",1,0.50\n"a,b",2,0.00\n)
  end
end
