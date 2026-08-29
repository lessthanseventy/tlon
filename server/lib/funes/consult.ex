defmodule Server.Consult do
  @moduledoc """
  The agent-to-agent consult (docs/plans/2026-08-17-agent-peer-consult-design.md): a
  correlated ask/answer pair between two agents on different threads. `consult_peer/3`
  delivers an ask to a peer's thread; `maybe_mirror/1` carries replies between the two
  sides for the life of the consult.

  The invariants the design review pinned: the caller never names a thread — only a peer
  agent name, resolved by server; server mediates every write through `Server.Channel.post`
  (the single writer); authors are always real identities; and the mirror is a
  bidirectional bridge keyed on `consult_id` with an echo guard (`mirrored`), so a
  mirrored copy is never re-mirrored.
  """
  import Ecto.Query

  alias Server.Agent
  alias Server.Channel
  alias Server.Message
  alias Server.Repo
  alias Server.Staff

  @doc """
  Ask a peer a question. `caller` is the MCP identity (`%{thread_id, agent_id, agent,
  session_id}`); `peer` is an agent NAME, never a thread id. Resolves the peer's target
  thread (agent-filtered, with a defined tie-break), creates the ask on that thread, and
  returns `{:ok, %{consult_id, peer_thread_id}}` or `{:error, reason}`.
  """
  def consult_peer(caller, peer, prompt) do
    with {:ok, agent} <- resolve_peer(peer),
         {:ok, thread} <- resolve_target(agent),
         {:ok, ask} <- create_ask(caller, thread, prompt) do
      {:ok, %{consult_id: ask.consult_id, peer_thread_id: thread.id}}
    end
  end

  @doc """
  The mirror: if `message` is a non-mirrored reply within a consult, copy it to the other
  side of the consult (bidirectional, keyed on `consult_id`). The echo guard — never
  mirror a message that is itself a mirror — is what stops ask→mirror→mirror-of-mirror→…
  forever. Returns `:ok` always; a non-consult message is a no-op.
  """
  def maybe_mirror(%Message{mirrored: true}), do: :ok
  def maybe_mirror(%Message{reply_to: nil}), do: :ok

  def maybe_mirror(%Message{reply_to: parent_id} = message) do
    case Repo.get(Message, parent_id) do
      %Message{consult_id: nil} -> :ok
      %Message{consult_id: consult_id} = parent -> mirror(message, parent, consult_id)
      nil -> :ok
    end
  end

  # The two sides of a consult come from the ASK (the one non-mirrored message with this
  # consult_id): its thread is the peer's, its origin_thread_id is the caller's. A message
  # on the caller's side mirrors to the peer's thread; a message on the peer's side mirrors
  # to the caller's. A message on neither side (shouldn't happen) is left alone.
  defp mirror(message, _parent, consult_id) do
    case find_ask(consult_id) do
      %Message{thread_id: peer_thread, origin_thread_id: caller_thread} ->
        other = if message.thread_id == caller_thread, do: peer_thread, else: caller_thread

        if other == message.thread_id do
          :ok
        else
          Channel.post(%{
            thread_id: other,
            author: message.author,
            body: message.body,
            origin_thread_id: caller_thread,
            consult_id: consult_id,
            mirrored: true
          })

          :ok
        end

      nil ->
        :ok
    end
  end

  # The ask is the one non-mirrored message carrying this consult_id — the peer's replies
  # and the caller's follow-ups are ordinary posts (no consult_id), so this is unambiguous.
  defp find_ask(consult_id) do
    Repo.one(from m in Message, where: m.consult_id == ^consult_id and m.mirrored == false)
  end

  defp resolve_peer(peer) do
    case Staff.agent_by_name(peer) do
      %Agent{} = agent -> {:ok, agent}
      nil -> {:error, :unknown_peer}
    end
  end

  # The defined target rule (design §2b, Hole 1): an agent maps to many threads, so resolve
  # over the peer's staffed threads and filter to live sessions BY AGENT (never
  # session_for_thread/1, which filters only by thread and could misroute on a stray
  # cross-agent session). 0 live → the most recent thread (durable, no liveness invented);
  # 1 live → there; >1 live → the most-recently-active by last_active_at (measured warmth,
  # not thread-id order).
  defp resolve_target(%Agent{} = peer) do
    threads = Staff.threads_for(peer)

    if threads == [] do
      {:error, :no_threads}
    else
      live =
        for t <- threads,
            s = Staff.live_session(t.id, peer.id),
            not is_nil(s),
            do: {t, s}

      case live do
        [] -> {:ok, hd(threads)}
        [{t, _}] -> {:ok, t}
        many -> {:ok, elem(Enum.max_by(many, fn {_t, s} -> s.last_active_at end), 0)}
      end
    end
  end

  # The ask: a message on the peer's thread, authored by the caller's real identity, carrying
  # the caller's thread as origin. server mediates the write through Channel.post — the caller
  # never writes cross-thread directly. The ask IS the consult root: its own id becomes the
  # consult_id (guaranteed unique, and within SQLite's signed-integer range — a random 64-bit
  # id overflows it).
  # One transaction for the post + the consult_id stamp: a crash between the two would leave
  # an orphan ask (consult_id NULL — an ordinary-looking message, the consult root lost). A
  # rolled-back post's Bus announce is the only residue, and readers re-query on announce.
  defp create_ask(caller, thread, prompt) do
    Repo.transaction(fn ->
      with {:ok, ask} <-
             Channel.post(%{
               thread_id: thread.id,
               author: caller.agent,
               body: prompt,
               origin_thread_id: caller.thread_id
             }),
           {:ok, stamped} <- Repo.update(Ecto.Changeset.change(ask, consult_id: ask.id)) do
        stamped
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
