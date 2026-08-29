defmodule Console.OscTest do
  use ExUnit.Case, async: true

  test "copy/1 builds an OSC 52 clipboard write with base64 payload" do
    assert Console.Osc.copy("abc123") == "\e]52;c;#{Base.encode64("abc123")}\a"
  end
end
