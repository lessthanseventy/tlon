defmodule Server.Jobs do
  @moduledoc """
  The one door onto the queue. Oban runs where the service runs (`TLON_START_OBAN=1`); a node
  without it (a dev shell, the embedded console) must still be able to *ask* for a job and
  hear an honest `{:error, :no_oban}` — never a `noproc` exit off an idle or a post.
  """

  @doc "Insert `changeset` when Oban is up on this node; `{:error, :no_oban}` otherwise."
  def enqueue(%Ecto.Changeset{} = changeset) do
    if Oban.Registry.whereis(Oban), do: Oban.insert(changeset), else: {:error, :no_oban}
  end
end
