defmodule Server.ScheduleRun do
  @moduledoc """
  One firing of a `Server.Schedule`: `running` until its work is handed over (an agent run, a
  workline) or done (a script: its `exit` and the tail of its `output`), then `ok` or `failed`.
  `thread_id` is where it landed. The automation board is these rows, newest first. A script that
  prints a line `ran-on: <check> <sha>` names the commit it checked (`check_name`, `sha`): what
  `Server.Release.Candidate` reads to say whether the gate passed on exactly a commit.
  """
  use Ecto.Schema

  schema "schedule_run" do
    field :status, :string, default: "running"
    field :exit, :integer
    field :output, :string
    field :check_name, :string
    field :sha, :string
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    belongs_to :schedule, Server.Schedule
    belongs_to :thread, Server.Thread
  end
end
