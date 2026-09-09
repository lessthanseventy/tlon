defmodule Server.Bus do
  @moduledoc """
  The reactive substrate over the durable bus (console §5). `Phoenix.PubSub` fans
  **typed events** out to **focused topics**, so a consumer subscribes to exactly
  what it needs — the switchboard to the message firehose, the board to one thread
  (IN SCOPE) or the roster (IN FLIGHT) — instead of filtering everything.

  This is *liveness only*: every event is already a durable row before it is
  broadcast, and a broadcast with no subscriber is a harmless no-op. Kill PubSub and
  nothing is lost; readers recover from the DB.

  ## Topics
    * `tlon:messages`     — every posted message (the switchboard's stream)
    * `tlon:thread:{id}`  — everything on one thread: messages, facts, events, issues,
                            todos, questions, sessions, presence, assignment/close (feeds IN SCOPE)
    * `tlon:threads`      — thread lifecycle: opened, closed, deleted, assigned, workline
                            advanced/gated (the list)
    * `tlon:sessions`     — session start/end (feeds the IN FLIGHT roster)
    * `tlon:presence`     — explicit thinking/idle declarations (`Server.Presence.Thinking`)
    * `tlon:habits`       — habit proposed/approved/rejected (the operator's review queue)
    * `tlon:workspaces`   — workspace registered/edited/removed (the console's picker/survey)
    * `tlon:projects`     — project registered/edited/removed
    * `tlon:notes`        — note written/edited/removed
    * `tlon:tickets`      — ticket filed/updated/removed
    * `tlon:activity`     — every durable write, cross-thread (the machine-wide activity feed)

  ## Events (the envelope every subscriber matches)
    `{:message_posted, message}` · `{:fact_banked, fact}` · `{:fact_forgotten, fact}`
    `{:event_recorded, event}` · `{:issue_raised, issue}` · `{:issue_resolved, issue}`
    `{:todo_added, todo}` · `{:todo_completed, todo}` · `{:question_raised, q}`
    `{:question_resolved, q}` · `{:habit_proposed, h}` · `{:habit_approved, h}`
    `{:habit_rejected, h}` · `{:workspace_registered, w}` · `{:workspace_edited, w}`
    `{:workspace_removed, w}` · `{:project_registered, p}` · `{:project_edited, p}`
    `{:project_removed, p}` · `{:note_written, n}` · `{:note_edited, n}` · `{:note_removed, n}`
    `{:ticket_filed, t}` · `{:ticket_updated, t}` · `{:ticket_removed, t}`
    `{:thread_opened, thread}` · `{:thread_closed, thread}` · `{:thread_deleted, thread}`
    `{:thread_assigned, thread}` · `{:workline_advanced, thread}` · `{:workline_gated, thread}`
    `{:session_started, s}` · `{:session_ended, s}`
    `{:presence_thinking, %{thread_id, agent, started_at}}` · `{:presence_idle, %{thread_id, agent}}`
  """
  @pubsub Server.PubSub

  def messages_topic, do: "tlon:messages"
  def thread_topic(id), do: "tlon:thread:#{id}"
  def threads_topic, do: "tlon:threads"
  def sessions_topic, do: "tlon:sessions"
  def presence_topic, do: "tlon:presence"
  def habits_topic, do: "tlon:habits"
  def workspaces_topic, do: "tlon:workspaces"
  def projects_topic, do: "tlon:projects"
  def notes_topic, do: "tlon:notes"
  def tickets_topic, do: "tlon:tickets"
  def activity_topic, do: "tlon:activity"

  def subscribe_messages, do: sub(messages_topic())
  def subscribe_thread(id), do: sub(thread_topic(id))
  def subscribe_threads, do: sub(threads_topic())
  def subscribe_sessions, do: sub(sessions_topic())
  def subscribe_presence, do: sub(presence_topic())
  def subscribe_habits, do: sub(habits_topic())
  def subscribe_workspaces, do: sub(workspaces_topic())
  def subscribe_projects, do: sub(projects_topic())
  def subscribe_notes, do: sub(notes_topic())
  def subscribe_tickets, do: sub(tickets_topic())
  def subscribe_activity, do: sub(activity_topic())

  # A consumer that follows the *focused* thread drops the old topic on a switch.
  def unsubscribe_thread(id), do: Phoenix.PubSub.unsubscribe(@pubsub, thread_topic(id))

  defp sub(topic), do: Phoenix.PubSub.subscribe(@pubsub, topic)

  @doc """
  Broadcast a typed event to the topic(s) it belongs on. Routing is centralized here
  so the topic scheme has one home. Returns `:ok`.
  """
  def broadcast({:message_posted, m} = event) do
    publish([messages_topic(), activity_topic() | thread_topics(m.thread_id)], event)
  end

  def broadcast({tag, %{thread_id: thread_id} = _row} = event)
      when tag in [
             :fact_banked,
             :fact_forgotten,
             :event_recorded,
             :issue_raised,
             :issue_resolved,
             :todo_added,
             :todo_completed,
             :question_raised,
             :question_resolved
           ] do
    publish([activity_topic() | thread_topics(thread_id)], event)
  end

  # Habits are machine-wide (no thread_id key of their own), so they ride their own topic
  # plus the topic of the thread that PROPOSED them (source_thread_id, for provenance) when
  # there was one — letting the cockpit's review surface and that thread both hear it.
  def broadcast({tag, %Server.Habit{} = habit} = event) when tag in [:habit_proposed, :habit_approved, :habit_rejected] do
    publish([habits_topic() | thread_topics(habit.source_thread_id)], event)
  end

  # Workspaces are machine-global (no thread_id of their own): they ride their own topic
  # plus the cross-thread activity feed.
  def broadcast({tag, %Server.Workspace{}} = event)
      when tag in [:workspace_registered, :workspace_edited, :workspace_removed] do
    publish([workspaces_topic(), activity_topic()], event)
  end

  # Projects are workspace-scoped (no thread_id of their own): their own topic + the
  # cross-thread activity feed, like workspaces.
  def broadcast({tag, %Server.Project{}} = event) when tag in [:project_registered, :project_edited, :project_removed] do
    publish([projects_topic(), activity_topic()], event)
  end

  # Notes carry a polymorphic scope (no single thread_id): their own topic + the activity feed.
  def broadcast({tag, %Server.Note{}} = event) when tag in [:note_written, :note_edited, :note_removed] do
    publish([notes_topic(), activity_topic()], event)
  end

  # Tickets are workspace-scoped (the lightweight tracker): their own topic + the activity feed.
  def broadcast({tag, %Server.Ticket{}} = event) when tag in [:ticket_filed, :ticket_updated, :ticket_removed] do
    publish([tickets_topic(), activity_topic()], event)
  end

  # Channels (UX slice 1b) live on the workspaces topic — the rail redraws on both; a moved
  # thread is a thread event.
  def broadcast({tag, %Server.ChannelRow{}} = event) when tag in [:channel_created, :channel_deleted] do
    publish([workspaces_topic(), activity_topic()], event)
  end

  @thread_tags [
    :thread_opened,
    :thread_closed,
    :thread_deleted,
    :thread_assigned,
    :thread_moved,
    :workline_advanced,
    :workline_gated
  ]

  def broadcast({tag, thread} = event) when tag in @thread_tags do
    publish([threads_topic() | thread_topics(thread.id)], event)
  end

  def broadcast({tag, session} = event) when tag in [:session_started, :session_ended] do
    publish([sessions_topic() | thread_topics(session.thread_id)], event)
  end

  # Presence is liveness-only (never a durable row), so it skips the activity feed.
  def broadcast({tag, %{thread_id: thread_id}} = event) when tag in [:presence_thinking, :presence_idle] do
    publish([presence_topic() | thread_topics(thread_id)], event)
  end

  # A thread-scoped row may be unscoped (nil): then it belongs on no thread topic.
  defp thread_topics(nil), do: []
  defp thread_topics(thread_id), do: [thread_topic(thread_id)]

  defp publish(topics, event) do
    Enum.each(topics, &Phoenix.PubSub.broadcast(@pubsub, &1, event))
  end

  @doc """
  Announce a successful write: broadcast `{tag, row}` on an `{:ok, row}`, and pass
  the result straight through untouched otherwise. Lets a context end a write with
  `|> Bus.announce(:thread_opened)` — the row is durable before the nudge fires.
  """
  def announce({:ok, row} = result, tag) do
    broadcast({tag, row})
    result
  end

  def announce(result, _tag), do: result
end
