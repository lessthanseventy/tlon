defmodule Server.Repo.Migrations.SessionOneLivePerThreadAgent do
  use Ecto.Migration

  # 015 the zombie guard (pi doc §4c.2). A crashed agent leaves `ended_at` NULL —
  # "reconciliation cannot depend on a clean exit" (§8, measured twice) — and a
  # replacement spawned beside it would leave TWO live sessions for one
  # (thread, agent): the switchboard's recipients/1 then wakes BOTH panes while
  # the zombie is still warm, a paid poke into a dead or half-alive pane.
  #
  # `Staff.start_session` supersedes (ends the predecessor in the same
  # transaction), but supersede-in-code is convention, and under a concurrent
  # register race convention loses. This partial UNIQUE index makes the DB itself
  # the guard (§10): at most one live session per (thread, agent). Per-AGENT, not
  # per-thread — multiple agents' sessions on one thread are coworkers, a feature.
  def change do
    create unique_index(:session, [:thread_id, :agent_id],
             where: "ended_at IS NULL",
             name: :session_one_live_per_thread_agent
           )
  end
end
