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

  @doc """
  Cancel job `id` when Oban is up on this node (`Oban.cancel_job/1`: one update through the repo, so
  inside a `Repo.transaction` it commits or rolls back with the caller); `{:error, :no_oban}` otherwise.
  """
  def cancel(id) when is_integer(id) do
    if Oban.Registry.whereis(Oban), do: Oban.cancel_job(id), else: {:error, :no_oban}
  end
end
