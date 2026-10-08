defmodule Server.Jobs do
  @moduledoc """
  The one door onto the queue. Oban runs where the service runs (`TLON_START_OBAN=1`); a node
  without it (a dev shell, a test) must still be able to *ask* for a job and
  hear an honest `{:error, :no_oban}` — never a `noproc` exit off an idle or a post.
  """

  @doc "Insert `changeset` when Oban is up on this node; `{:error, :no_oban}` otherwise."
  def enqueue(%Ecto.Changeset{} = changeset) do
    if Oban.Registry.whereis(Oban), do: Oban.insert(changeset), else: {:error, :no_oban}
  rescue
    # a db fault while enqueueing is the caller's error to handle, never a raise through a GenServer
    e -> {:error, Exception.message(e)}
  end
end
