defmodule Console.Panel.NewThread do
  @moduledoc """
  The persistent **new-thread** input — a band at the bottom of the chat window, above the tertius
  orchestrator line (2026-09-01, Andrew: "each thread gets a reply; the chat window gets one that
  starts a new thread; the orchestrator is at the very bottom" — three input tiers, no keybind).

  Always visible: an idle placeholder invites a title; click (or `n`) focuses it, and its live buffer
  renders with a caret while the `:new_thread` input is active. Enter creates the thread (keymap →
  `{:create_thread, …}`). Data is `%{input: input_map | nil}`. Pure render.
  """
  @behaviour Console.Panel

  @placeholder "‹＋ start a new thread… — click to type›"

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  def render(%{input: %{kind: :new_thread, buffer: buffer}}, rect),
    do: Console.Panel.clip([[{"＋ new thread ▸ ", :st_working}, {buffer, :normal}, {"▎", :accent}]], rect)

  def render(_data, rect),
    do: Console.Panel.clip([[{"＋ ", :st_working}, {@placeholder, :dim}]], rect)
end
