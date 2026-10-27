defmodule Server.Authorship do
  @moduledoc """
  Who wrote a row, verifiably (#679): the one place the format lives. A row stamped with the
  session that wrote it renders `<seat> · pane t<thread> <pane> · session <id>`, so a denial
  ("that wasn't me") is checked against a record rather than a name. A NULL session renders
  `session unknown`: a row from before the stamp, a system author's, or a call before `register`
  bound a session. Never inferred.
  """

  alias Server.Repo
  alias Server.Session

  @doc "`author`'s label with the session that wrote the row, e.g. `nolan · pane t281 %9 · session 954`."
  @spec label(String.t(), integer() | nil) :: String.t()
  def label(author, session_id), do: "#{author} · #{session_label(session_id)}"

  @doc "The session part alone: `pane t281 %9 · session 954`, `session 954` with no pane, `session unknown` for nil or a row gone."
  @spec session_label(integer() | nil) :: String.t()
  def session_label(nil), do: "session unknown"

  def session_label(id) do
    case Repo.get(Session, id) do
      %Session{thread_id: t, pane_ref: pane} when is_binary(pane) -> "pane t#{t} #{pane} · session #{id}"
      %Session{} -> "session #{id}"
      nil -> "session unknown"
    end
  end
end
