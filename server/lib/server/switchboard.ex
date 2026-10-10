defmodule Server.Switchboard do
  @moduledoc """
  The switchboard — **liveness over the durable bus** (§10, §5b.2). A
  message is already a row when it is posted (`Server.Channel`); the switchboard's
  only job is to make delivery *live*: decide who to wake and poke their pane
  through the arbiter. It must never be what makes a message *exist* — kill the
  BEAM node and every message is still a row, and `drain/0` re-delivers on restart,
  so no wake is lost.

  `delivered_at` in the DB is the durable truth of what was delivered; PubSub (the
  `Server`) is only the low-latency nudge.

  ## Addressed delivery — a message wakes who it is addressed to, not the room

  A plain top-level post wakes only the thread's **lead** (its assigned agent, the
  orchestrator); an **@mention** wakes that coworker; a **reply** wakes the author of
  the message it answers. Never the whole room — the lead stays informed because
  coworkers report back to the thread. See `recipients/1`.

  Only the crew on shift is woken. A message for a thread's off-shift lead goes to whoever
  does that job on shift (the same archetype, else the manager), in their own window; one
  for anyone else off shift waits, undelivered, for their crew.

  ## Two guard-rails against burning a five-hour window

  Waking pokes a *real, paid* agent session, so the wake is deliberately restrained:

  1. **Coalescing.** A backlog wakes each pane ONCE, never once per message — a
     resumed thread with fifty undelivered messages is one nudge, not fifty turns
     (`drain/0` dedups panes; also §5b's noise rule).
  2. **Warmth-gating.** A session idle longer than the prompt cache stays
     warm (~1h, `:warmth_window_seconds`) is **cold** — a poke would pay a full
     transcript re-ingestion instead of a cheap resume, the "resumed an old thread
     and burned my whole allotment" footgun. `recipients/1` excludes cold sessions
     (treated like ended ones), and the switchboard bumps `last_active_at` as a
     session acts — on being woken and on authoring (§3b, the warmth window).
     The OTHER half of "clocked out" — an engine out of credits or past its
     rate-limit window — gates the wake too: `recipients/1` drops a session whose
     engine `Server.Presence.Engine.clocked_out?/1` reports spent (a pluggable §8
     backend, defaulting to always-available).

  With no arbiter configured (the headless service) every wake is bookkeeping only: the
  message is claimed as delivered, the recipient's warmth bumped, nothing poked.
  """
  import Ecto.Query

  alias Server.Agent
  alias Server.Arbiter
  alias Server.MCP.Spawn
  alias Server.Mentions
  alias Server.Message
  alias Server.Presence
  alias Server.Repo
  alias Server.Session
  alias Server.Staff
  alias Server.Thread

  require Logger

  # a session active more than this after its wake made a call of its own: it heard the message
  @heard_after 5

  @doc """
  Deliver one message (the live path): wake its addressed recipients (`recipients/1`),
  then stamp it delivered. A message no one live is addressed to stays undelivered
  (`:pending`) — it is not a delivery until someone is woken (§5b.3), and `drain/0`
  picks it up when a recipient appears. Returns `{:delivered, message}`,
  `{:pending, message}`, or `{:already_delivered, message}` when a concurrent drain
  won the claim first.
  """
  def deliver(%Message{} = message) do
    # Authoring is activity: keep the author's session warm even when nobody is woken
    # (a lead's report up to the human keeps the lead warm).
    touch_author(message)

    # The pane is sitting on a dialog (Server.Attention): typing a message into it would answer
    # the dialog with garbage. Hold; the drain re-delivers once the prompt is resolved. A restart
    # waiting for quiet holds every new wake too, so the bench drains instead of starting turns
    # the restart would cut; the drain after it delivers them.
    if is_nil(message.delivered_at) and
         (Server.Attention.waiting?(message.thread_id) or Server.Rollout.restart_pending?()),
       do: {:pending, message},
       else: deliver_now(message)
  end

  defp deliver_now(%Message{} = message) do
    case recipients(message) do
      [] ->
        # Nobody warm+available is addressed — open panes for whoever it addresses (§4c.3) rather
        # than wait for the human. Delivery happens when they come up, so this stays :pending.
        maybe_spawn_absent(message)
        {:pending, message}

      sessions ->
        # Claim delivery ATOMICALLY, then wake — so the drain and the live handler
        # racing over the same message at startup can never both poke a paid pane.
        # Whoever flips delivered_at from NULL is the only one who wakes.
        if claim([message.id]) > 0, do: wake_claimed(message, sessions), else: {:already_delivered, message}
    end
  end

  defp wake_claimed(message, sessions) do
    case waken(sessions, message) do
      # every pane it was for has closed (a restart took the windows): not a delivery — those
      # sessions ended, it is pending again, and whoever it addresses is spawned fresh
      [] ->
        unclaim([message.id])
        maybe_spawn_absent(message)
        {:pending, message}

      _reached ->
        {:delivered, message}
    end
  end

  @doc """
  Deliver everything still undelivered, oldest first — the durability path (§10),
  run on switchboard start so messages posted while it was down are still woken.
  COALESCED per recipient: each distinct pane is woken ONCE for the whole backlog
  (the burst guard), and only the messages that actually reached someone are marked
  delivered.
  """
  def drain do
    if Server.Rollout.restart_pending?(), do: :ok, else: drain_now()
  end

  @doc """
  Hand back for re-delivery a wake nobody heard: a message delivered 10–30 minutes ago whose every
  addressed session has made no call to the server since the wake itself (`@heard_after` of slack
  for the wake's own warmth bump). That is a turn whose calls all failed — the server unreachable,
  its working directory gone — ending on a promise to retry that nothing would otherwise keep. The
  next `drain/0` wakes them again; past 30 minutes from its posting a message is let go (a routed
  ticket has the intake's own rescue). Returns how many were handed back.
  """
  def redeliver_unheard(now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -30 * 60)
    settled = DateTime.add(now, -10 * 60)

    ids =
      from(m in Message,
        where: not is_nil(m.delivered_at) and m.delivered_at <= ^settled and m.created_at >= ^since
      )
      |> Repo.all()
      |> Enum.filter(&unheard?/1)
      |> Enum.map(& &1.id)

    if ids != [], do: unclaim(ids)
    length(ids)
  end

  defp unheard?(message) do
    heard_by = DateTime.add(message.delivered_at, @heard_after)

    case recipients(message) do
      [] ->
        false

      sessions ->
        Enum.all?(sessions, &(is_nil(&1.last_active_at) or DateTime.compare(&1.last_active_at, heard_by) != :gt))
    end
  end

  # For drain: bump the author's warmth, then return the recipient sessions this call
  # actually claimed — empty if the message is unaddressed or a concurrent deliver
  # already won its claim.
  defp claim_reached(message) do
    touch_author(message)

    case recipients(message) do
      [] ->
        # nobody warm is addressed: open their panes (a no-op while one is still booting); a message
        # that can reach nobody at all is settled, or every drain would read it again forever
        if reaches_nobody?(message), do: claim([message.id]), else: maybe_spawn_absent(message)
        []

      sessions ->
        if claim([message.id]) > 0, do: Enum.map(sessions, &{&1, message.id}), else: []
    end
  end

  defp reaches_nobody?(%Message{kind: kind}) when kind in ["notice", "suggestion", "margin"], do: true

  defp reaches_nobody?(%Message{} = message) do
    author = String.downcase(message.author)

    match?(%Thread{state: "closed"}, Repo.get(Thread, message.thread_id)) or
      message |> addressed() |> Enum.all?(&(String.downcase(&1) == author))
  end

  # An off-shift seat is never woken. A message for its thread's off-shift lead goes to whoever does
  # that job on shift (the same archetype, else the manager); one for anyone else off shift waits.
  defp on_shift(names, thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{workspace_id: ws, agent_id: lead_id} when is_integer(ws) ->
        on = Server.Workspaces.bench(ws)
        on_ids = MapSet.new(on, & &1.agent_id)
        off = ws |> Server.Workspaces.bench_all() |> Enum.reject(&MapSet.member?(on_ids, &1.agent_id))

        names
        |> Enum.flat_map(
          &(off
            |> Enum.find(fn seat -> String.downcase(seat.name) == String.downcase(&1) end)
            |> for_shift(&1, lead_id, on, ws))
        )
        |> Enum.uniq()

      _ ->
        names
    end
  end

  defp for_shift(nil, name, _lead_id, _on, _ws), do: [name]
  defp for_shift(%{agent_id: lead_id} = seat, _name, lead_id, on, ws), do: stand_in(seat, on, ws)
  defp for_shift(_off_seat, _name, _lead_id, _on, _ws), do: []

  defp stand_in(seat, on, ws) do
    case Enum.find(on, &(&1.archetype == seat.archetype)) || Server.Workspaces.manager(ws) do
      nil -> []
      coworker -> [coworker.name]
    end
  end

  # Atomically flip delivered_at to now for the still-undelivered messages among
  # `ids`, returning how many this call actually claimed. The `is_nil` guard in the
  # WHERE is the race gate: exactly one caller wins each message, so exactly one
  # wakes for it. `delivered_at` is the durable delivery truth (§10), so the claim
  # is both the record and the lock.
  defp claim(ids) do
    stamp = DateTime.truncate(DateTime.utc_now(), :second)

    {count, _} =
      Repo.update_all(
        from(m in Message, where: m.id in ^ids and is_nil(m.delivered_at)),
        set: [delivered_at: stamp]
      )

    count
  end

  # Who a message wakes (the addressed-delivery model):
  #   * a REPLY  -> the author of the message it replies to
  #   * @mentions -> the named coworkers — one with no place on this thread (not on it, not its
  #     lead) in their own window on the workspace's standing thread, told how to answer
  #   * neither (a plain top-level post) -> the thread's LEAD (its assigned agent)
  #   * a `notice` -> nobody: it is read on the next turn; a corkboard `suggestion` or a `margin` note, nobody ever
  #   * anyone off shift -> never: a lead's stand-in on shift instead, anyone else waits (`on_shift/2`)
  # minus the message's own author — you are never woken by your own words. The
  # lead stays informed without being cc'd because coworkers report back to the
  # thread (their top-level posts wake the lead).
  defp recipients(%Message{kind: kind}) when kind in ["notice", "suggestion", "margin"], do: []

  defp recipients(%Message{} = message) do
    # Match author↔agent case-INSENSITIVELY throughout (as @mentions already do), so
    # a mis-cased author handle can't silently drop a reply or strand an agent cold.
    author = String.downcase(message.author)
    targets = message |> target_names() |> Enum.reject(&(String.downcase(&1) == author))

    case targets do
      [] ->
        []

      names ->
        thread = Repo.get(Thread, message.thread_id)
        ws = thread && thread.workspace_id
        here = warm_sessions(message.thread_id, names, ws)
        found = MapSet.new(here, fn {_session, agent} -> String.downcase(agent.name) end)

        # someone named here who has no place on this thread hears it where they live: their window
        # on the workspace's standing thread
        away =
          for name <- names,
              not MapSet.member?(found, String.downcase(name)),
              lobby = elsewhere(thread, name),
              lobby != nil,
              pair <- warm_sessions(lobby, [name], ws),
              do: pair

        Enum.map(here ++ away, &elem(&1, 0))
    end
  end

  # Only WARM sessions of `names` on `thread_id`: live, addressed, and active within the cache window.
  # A cold session is treated like an ended one — never poked (§3b).
  defp warm_sessions(thread_id, names, ws) do
    wanted = Enum.map(names, &String.downcase/1)
    cutoff = Presence.loosest_cutoff()

    from(s in Session,
      join: a in Agent,
      on: a.id == s.agent_id,
      where:
        s.thread_id == ^thread_id and is_nil(s.ended_at) and
          fragment("lower(?)", a.name) in ^wanted and s.last_active_at > ^cutoff,
      select: {s, a}
    )
    |> Repo.all()
    # each by its own provider's window (`Presence.warm_for?/4`; one window unless configured)
    |> Enum.filter(fn {session, agent} -> Presence.warm_for?(session.last_active_at, agent.name, ws) end)
    # Then the ENGINE-CREDIT half of clocked-out: drop a session whose model is
    # out of credits / past its rate-limit window (§3b). A pluggable backend
    # (§8) — the SQL can't ask a vendor, so it is a post-filter on small N.
    |> Enum.reject(fn {_session, agent} -> Presence.clocked_out?(agent) end)
  end

  # Where a coworker named on `thread` with no place on it is reached: the workspace's standing
  # thread, where each coworker has a window of their own — unless this is that thread, or they
  # lead this one (then it is here they are woken, or spawned). nil when there is nowhere else.
  defp elsewhere(%Thread{workspace_id: ws} = thread, name) when not is_nil(ws) do
    with %Thread{id: lobby, state: "open"} when lobby != thread.id <- Server.Channel.machine_thread(ws),
         %Agent{id: id} when id != thread.agent_id <- Staff.agent_by_name(name) do
      lobby
    else
      _ -> nil
    end
  end

  defp elsewhere(_thread, _name), do: nil

  # Staffing on demand (§4c.3): nobody runs ahead of need, so a message addressed to coworkers with
  # no warm session on its thread opens a pane for each it may — the thread's LEAD anywhere, any
  # addressed coworker on the workspace's standing thread (one window each there; elsewhere a
  # thread has one leaf, its lead's). The SAME arbiter seam the `s` verb uses (`Spawn` mints
  # identity, `Arbiter` actuates). Gated: no warm session (a cold one is rotated onto a fresh,
  # brief-seeded pane, never resumed), an open thread (a closed one's backlog wakes nobody), and an
  # engine not clocked out (a fresh session it cannot run is worse than waiting). A pane already
  # running (its coworker still booting) is left alone, which makes the drain's retry each minute safe.
  defp maybe_spawn_absent(%Message{thread_id: thread_id} = message) do
    with %Thread{state: "open"} = thread <- Repo.get(Thread, thread_id) do
      author = String.downcase(message.author)
      standing? = match?(%Thread{id: ^thread_id}, Server.Channel.machine_thread(thread.workspace_id))

      # only the lead or a bench seat is ours to staff: an outside citizen (`Server.Outside`) runs its own session
      benched =
        if thread.workspace_id,
          do: MapSet.new(Server.Workspaces.bench(thread.workspace_id), & &1.agent_id),
          else: MapSet.new()

      spawned =
        for name <- target_names(message),
            String.downcase(name) != author,
            %Agent{} = agent <- [Staff.agent_by_name(name)],
            agent.id == thread.agent_id or agent.id in benched,
            home = spawn_home(thread, agent, standing?),
            home != nil,
            not has_warm_session?(home, agent),
            not Presence.clocked_out?(agent),
            # a window of their own there: never the thread's lead because they were named on it
            {:ok, %{exports: exports}} <- [Spawn.join(home.id, agent.name, assign: false)],
            {:ok, handle} <- [Arbiter.spawn(exports)],
            do: {agent.name, handle, home.id}

      if spawned != [], do: opening_turn(message, spawned)
    end

    :ok
  end

  # Where an absent coworker named on `thread` is spawned: here if this is the standing thread or they
  # lead it; anyone else in their own window on the standing thread (`elsewhere/2`).
  defp spawn_home(thread, agent, standing?) do
    cond do
      standing? or agent.id == thread.agent_id -> thread
      lobby = elsewhere(thread, agent.name) -> Repo.get(Thread, lobby)
      true -> nil
    end
  end

  # The spawned panes' OPENING TURN. A harness that registers only on its first prompt (Claude Code)
  # would otherwise wait forever for a wake that waits for it to register. Off the caller's path:
  # once every pane is ready (or the wait runs out), CLAIM the message — the claim is what keeps a
  # concurrent drain from typing it a second time once a session does register — and wake each new
  # window with it, exactly the poke a warm session would have got.
  defp opening_turn(%Message{} = message, spawned) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Server.TaskSupervisor, fn ->
        budget = Application.get_env(:server, :spawn_ready_timeout_ms, 20_000)
        Enum.each(spawned, fn {_agent, handle, _home} -> await_ready(handle, budget) end)

        if claim([message.id]) > 0, do: poke_spawned(message, spawned)
      end)

    :ok
  end

  defp poke_spawned(message, spawned) do
    for {agent, _handle, home} <- spawned,
        do: poke(%{thread_id: home, agent: agent, pane_ref: nil}, prompt_for(message, home))
  end

  defp await_ready(handle, budget_ms) do
    poll = Application.get_env(:server, :spawn_ready_poll_ms, 500)

    cond do
      Arbiter.ready?(handle) ->
        true

      budget_ms <= 0 ->
        false

      true ->
        Process.sleep(poll)
        await_ready(handle, budget_ms - max(poll, 1))
    end
  end

  # A WARM session is one worth waking (a cheap resume): live AND active within the warmth window.
  # A cold session (stale last_active_at) is treated as ABSENT so the lead gets ROTATED — a fresh
  # brief-seeded session, never a /resume of a huge stale context (2026-09-01). The old
  # `has_live_session?` (ended_at-only) stranded a cold lead: recipients wouldn't wake it (too cold)
  # and this wouldn't replace it (a session existed). The fresh spawn's Staff.start_session
  # supersedes the cold session on connect (the zombie guard), so the rotation leaves no double.
  defp has_warm_session?(%Thread{} = thread, %Agent{} = agent) do
    cutoff = Presence.loosest_cutoff()

    from(s in Session,
      where:
        s.thread_id == ^thread.id and s.agent_id == ^agent.id and is_nil(s.ended_at) and
          s.last_active_at > ^cutoff,
      select: s.last_active_at
    )
    |> Repo.all()
    |> Enum.any?(&Presence.warm_for?(&1, agent.name, thread.workspace_id))
  end

  # Who is addressed, the author never among them — so a post whose only mention is its own author
  # ("report back to @me") is addressed to nobody else, and wakes the lead like any plain post.
  defp target_names(%Message{} = message), do: message |> addressed() |> on_shift(message.thread_id)

  # Who a message names, shift aside: what `reaches_nobody?/1` judges, so a message for someone off
  # shift is held for their crew rather than settled.
  defp addressed(%Message{} = message) do
    author = String.downcase(message.author)

    case Enum.reject(reply_author(message) ++ mentioned_agents(message), &(String.downcase(&1) == author)) do
      [] -> lead_name(message)
      addressed -> Enum.uniq(addressed)
    end
  end

  defp reply_author(%Message{reply_to: nil}), do: []

  defp reply_author(%Message{reply_to: parent_id}) do
    case Repo.get(Message, parent_id) do
      %Message{author: author} -> [author]
      nil -> []
    end
  end

  # The @-handles that name a real agent — an @here that matches no agent wakes no
  # one, and (because it resolves to nothing) does not suppress the lead default.
  # Matched case-INSENSITIVELY so a wrong-case @robert still reaches Robert rather
  # than silently falling back to the lead; the agent's real name is returned.
  defp mentioned_agents(%Message{body: body}) do
    case Mentions.names(body) do
      [] ->
        []

      handles ->
        wanted = Enum.map(handles, &String.downcase/1)
        Repo.all(from a in Agent, where: fragment("lower(?)", a.name) in ^wanted, select: a.name)
    end
  end

  defp lead_name(%Message{thread_id: thread_id}) do
    with %Thread{agent_id: agent_id} when not is_nil(agent_id) <- Repo.get(Thread, thread_id),
         %Agent{name: name} <- Repo.get(Agent, agent_id) do
      [name]
    else
      _ -> []
    end
  end

  # Poke each distinct recipient thread once, and bump the woken sessions warm — being woken is
  # a turn, so it refreshes their warmth. A session whose pane has closed is ended instead. The
  # sessions it reached.
  defp waken(sessions, message) do
    {gone, reached} =
      sessions
      |> Enum.uniq_by(&pane_of/1)
      |> Enum.split_with(&(poke(&1, prompt_for(message, &1.thread_id)) == :gone))

    Enum.each(gone, &end_gone/1)
    Staff.touch_sessions(Enum.map(reached, & &1.id), now())
    reached
  end

  # A session's pane: its coworker's own window on a standing thread, else the thread's one leaf.
  defp pane_of(%{thread_id: thread_id} = session) do
    with %Thread{workspace_id: ws} when not is_nil(ws) <- Repo.get(Thread, thread_id),
         %Thread{id: ^thread_id} <- Server.Channel.machine_thread(ws) do
      {thread_id, session.agent_id}
    else
      _ -> thread_id
    end
  end

  # a live session whose pane has closed is over: ended, so the next message spawns its coworker
  defp end_gone(%Session{} = session), do: Staff.end_session(session)
  defp end_gone(_session), do: :ok

  defp unclaim(ids), do: Repo.update_all(from(m in Message, where: m.id in ^ids), set: [delivered_at: nil])

  # Actuate one wake through the configured arbiter. No backend wired (`:no_arbiter`) is the
  # always-up service's normal state — the row is claimed and the display-owning node's arbiter
  # is what pokes — so it's a debug line, never a warning per message; a real backend's failure
  # (a dead terminal) is surfaced, because a lost nudge should be visible.
  defp poke(session, prompt) do
    case Arbiter.wake(session, prompt) do
      :ok ->
        :ok

      {:error, :no_arbiter} ->
        Logger.debug("switchboard: no arbiter on this node — #{inspect(session.pane_ref)} not poked")

      {:error, :no_window} ->
        :gone

      {:error, reason} ->
        Logger.warning("arbiter failed to wake #{inspect(session.pane_ref)}: #{inspect(reason)}")
    end
  end

  # Bump the author's live sessions on the thread to when they posted — authoring
  # is a turn. Forward-only via `Staff.touch_sessions/2` (warmth's one write path,
  # shared with the MCP channel), so a backlog drain never moves warmth backward.
  defp touch_author(%Message{thread_id: thread_id, author: author, created_at: at}) do
    down = String.downcase(author)

    ids =
      Repo.all(
        from s in Session,
          join: a in Agent,
          on: a.id == s.agent_id,
          where:
            s.thread_id == ^thread_id and is_nil(s.ended_at) and
              fragment("lower(?)", a.name) == ^down,
          select: s.id
      )

    Staff.touch_sessions(ids, at)
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)

  # the message id lets the session check the wake against the record (get_messages, search_history)
  defp prompt(%Message{id: id, author: author, body: body, thread_id: thread_id}) do
    "New message on thread #{thread_id} from #{author} (message ##{id}): #{body}"
  end

  # The wake for a session on `thread_id`: a message from another thread says how to answer it there
  defp prompt_for(%Message{thread_id: thread_id} = message, thread_id), do: prompt(message)

  defp prompt_for(%Message{author: author, thread_id: other} = message, _elsewhere),
    do:
      prompt(message) <>
        " (It's from thread #{other}, not this window's: if you lead it, answer there with post_message thread_id: #{other}; otherwise ask #{author} with consult_peer.)"

  defp drain_now do
    undelivered =
      Repo.all(from m in Message, where: is_nil(m.delivered_at), order_by: [asc: m.id])

    # Claim each message before collecting its recipients, so a wake is scoped to
    # what THIS drain actually claimed — a message a concurrent deliver already took
    # contributes nothing here.
    reached = Enum.flat_map(undelivered, &claim_reached/1)

    # Coalesce per recipient thread, keeping the COUNT §3b wants ("you have 50 unread") — one
    # nudge per recipient, never one per message. A thread whose pane has closed gets its
    # messages back as undelivered (its sessions ended), for the next drain to spawn someone.
    reached
    |> Enum.group_by(fn {session, _id} -> session.thread_id end)
    |> Enum.each(fn {_thread_id, [{session, _} | _] = pairs} ->
      case poke(session, "you have #{length(pairs)} unread message(s) on your threads") do
        :gone ->
          pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq_by(& &1.id) |> Enum.each(&end_gone/1)
          pairs |> Enum.map(&elem(&1, 1)) |> unclaim()

        _ ->
          pairs |> Enum.map(&elem(&1, 0).id) |> Enum.uniq() |> Staff.touch_sessions(now())
      end
    end)
  end
end
