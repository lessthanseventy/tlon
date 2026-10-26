defmodule Server.Repo.Migrations.StageMergedToLanded do
  @moduledoc false
  use Ecto.Migration

  # The terminal stage was named for GitHub's merge, which it precedes: a landed workline's PR still
  # waits on GitHub. Rows move over; the stage CHECK (named by Postgres from the baseline's inline one)
  # is swapped before the update (and `stage_advanced` events naming it are rewritten, which the landed-workline readers match) so `landed` is admitted, and the reverse on the way down.
  def up, do: swap("merged", "landed")
  def down, do: swap("landed", "merged")

  defp swap(from, to) do
    execute("ALTER TABLE thread DROP CONSTRAINT thread_stage_check")
    execute("UPDATE thread SET stage = '#{to}' WHERE stage = '#{from}'")

    execute("""
    UPDATE event SET detail = jsonb_set(detail::jsonb, '{to}', '"#{to}"')::text
    WHERE kind = 'stage_advanced' AND detail::jsonb ->> 'to' = '#{from}'
    """)

    execute("""
    ALTER TABLE thread ADD CONSTRAINT thread_stage_check
      CHECK (stage IN ('intent', 'spec', 'plan', 'build', 'verify', 'review', '#{to}'))
    """)
  end
end
