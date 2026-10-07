defmodule Server.Office.Focus do
  @moduledoc """
  "Show the operator thread N" — asked by one surface, acted on by another: the desktop's alert
  asks, the office TUI (which polls `GET /api/office/focus`) opens the thread. Only the newest
  request is kept, stamped with its time in ms, so a surface acts on each one once. Nothing durable:
  a request nobody acted on before a restart is stale anyway.
  """

  @key {__MODULE__, :latest}

  @doc "Ask the operator's surfaces to show thread `id`."
  def request(id) when is_integer(id),
    do: :persistent_term.put(@key, %{thread_id: id, at: System.system_time(:millisecond)})

  @doc "The newest request, or nil."
  def latest, do: :persistent_term.get(@key, nil)
end
