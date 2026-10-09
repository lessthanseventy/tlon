Code.require_file("../lib/report.ex", __DIR__)
ExUnit.start()

defmodule ReportTest do
  use ExUnit.Case

  @rows [%{name: "gate", runs: 7, ratio: 0.857}, %{name: "smoke", runs: 3, ratio: 1}]

  test "the text table" do
    assert Report.render(@rows) ==
             """
             check         runs   pass
             gate             7   0.86
             smoke            3   1.00
             total           10
             """
  end
end
