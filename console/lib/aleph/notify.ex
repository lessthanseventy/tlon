defmodule Console.Notify do
  @moduledoc """
  Native desktop notifications, the pure half (design: the operator can be on another
  workspace and still learn that an agent finished or is WAITING on them). console holds the
  host tty, and modern terminals (ghostty, on Linux AND macOS) turn an OSC 777 escape into a
  real desktop notification — platform-agnostic with zero per-OS dependencies, and it rides
  SSH for free. The host terminal also owns focus policy (notify only when unfocused), which
  console can't know from inside.

  This module only DECIDES and FORMATS: `for_event/2` maps an operator-relevant Bus event to
  `{title, body}` (nil for noise), `osc/2` builds the escape. The one-line tty write lives in
  the Cockpit (thin edge). `question_raised`/`issue_raised` now reach the cockpit cross-thread:
  the Cockpit subscribes to `Server.Bus`'s global `activity` topic, so these fire for ANY thread,
  not just the focused one (the meta-topic that was once outstanding server work).
  """

  @doc """
  The `{title, body}` for an operator-relevant event, or nil for events that shouldn't
  interrupt (repaint-only noise like `fact_banked`). The waiting-on-you kinds (a question, a
  raised issue) and completions (a session ending) are the interruptions worth having.
  """
  @spec for_event(atom(), map()) :: {String.t(), String.t()} | nil
  def for_event(:question_raised, row), do: {"tlon — question for you", text_of(row, [:text])}
  def for_event(:issue_raised, row), do: {"tlon — issue raised", "#{row_author(row)}#{text_of(row, [:summary])}"}

  def for_event(:session_ended, row),
    do: {"tlon — session ended", "#{row_agent(row)} finished (thread #{row_thread(row)})"}

  def for_event(:workline_gated, row),
    do:
      {"tlon — gate awaits you",
       "“#{Map.get(row, :title)}” parked at #{Map.get(row, :stage)} — approve #{Map.get(row, :id)}"}

  def for_event(_tag, _row), do: nil

  @doc """
  The OSC 777 notify escape (`ESC ] 777;notify;title;body BEL`). The title must not contain
  `;` (it would truncate into the body slot), and neither part may smuggle ESC/BEL — a Bus
  row's text is agent-authored, so this is an injection boundary, not cosmetics.
  """
  @spec osc(String.t(), String.t()) :: String.t()
  def osc(title, body) do
    "\e]777;notify;" <> String.replace(clean(title), ";", ",") <> ";" <> clean(body) <> "\a"
  end

  defp clean(text), do: String.replace(text, ~r/[\x00-\x1f\x7f]/, " ")

  defp text_of(row, keys), do: Enum.find_value(keys, "(no detail)", &Map.get(row, &1))
  defp row_author(row), do: if(by = Map.get(row, :found_by), do: "#{by}: ", else: "")
  # The event's :agent is a belongs_to — a preloaded %Agent{}, a bare name, or an unloaded
  # association. Only a name is safe to interpolate; anything else falls back.
  defp row_agent(row) do
    case Map.get(row, :agent) do
      %{name: name} when is_binary(name) -> name
      name when is_binary(name) -> name
      _ -> "a session"
    end
  end

  defp row_thread(row), do: Map.get(row, :thread_id) || "?"
end
