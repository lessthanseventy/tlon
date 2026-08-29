defmodule Sample do
  @moduledoc "A tiny fixture module for the manos-lspd integration test."

  def greet(name) do
    "hello, #{name}"
  end

  def add(a, b), do: a + b
end
