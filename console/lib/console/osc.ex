defmodule Console.Osc do
  @moduledoc """
  OSC escape builders — pure strings; the caller owns the tty write. OSC 52 sets the system
  clipboard THROUGH the terminal, so it works over SSH (the terminal, not the host, owns the
  clipboard). kitty honors it natively.
  """

  @doc """
  OSC 52: copy `text` to the system clipboard (`c` selection), base64-encoded.

      iex> Console.Osc.copy("abc123")
      "\\e]52;c;YWJjMTIz\\a"
  """
  @spec copy(String.t()) :: String.t()
  def copy(text), do: "\e]52;c;#{Base.encode64(text)}\a"
end
