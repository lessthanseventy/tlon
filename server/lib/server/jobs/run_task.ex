defmodule Server.Jobs.RunTask do
  @moduledoc """
  A coworker's long check, run by the service (`run_task`): one of `tasks/0` on the committed head
  of its checkout, in the verify script's throwaway checkout and branch mode (`RUN_TASK`), off the
  seat's sandbox. The result is posted on the thread to the caller by name, which wakes them, so a
  long suite never holds a pane in a foreground call. Only the committed head runs: what is not
  committed is not in it. One attempt: a retry would run the suite twice.
  """
  use Oban.Worker, queue: :tasks, max_attempts: 1

  @tasks ~w(check server:check server:test office:check office:test adapters:claude-code:check menard:check)

  @doc "The mise tasks a coworker may run here."
  def tasks, do: @tasks

  @doc "Queue `task` for `agent` on thread `tid`, on the committed head of checkout `tree`. `{:ok, job}` | `{:error, why}`."
  def enqueue(tid, agent, task, tree) do
    with true <- task in @tasks || {:error, "#{task} is not a task run_task runs; it runs: #{Enum.join(@tasks, ", ")}"},
         {sha, 0} <- System.cmd("git", ["-C", tree, "rev-parse", "HEAD"], stderr_to_stdout: true) do
      %{thread_id: tid, agent: agent, task: task, ref: String.trim(sha), tree: tree} |> new() |> Oban.insert()
    else
      {:error, _} = error -> error
      {out, _} -> {:error, "#{tree} has no commit to run: #{String.trim(out)}"}
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        id: id,
        args: %{"thread_id" => tid, "agent" => agent, "task" => task, "ref" => ref, "tree" => tree}
      }) do
    {out, code} =
      System.cmd("bash", [script(), "-", "task-#{id}", tree],
        env: [
          {"WORKLINE_GATE", "1"},
          {"LAND_REF", ref},
          {"RUN_TASK", task},
          {"CHECKS_LABEL", "##{tid} #{task} for #{agent}"}
        ],
        stderr_to_stdout: true
      )

    run = "`mise run #{task}`"
    on = String.slice(ref, 0, 7)

    body =
      if code == 0,
        do: "@#{agent} ✓ #{run} passed on #{on}",
        else: "@#{agent} ✗ #{run} failed (exit #{code}) on #{on}:\n```\n#{tail(out)}\n```"

    {:ok, _} = Server.Channel.post(%{thread_id: tid, author: "tlon", body: body})
    :ok
  end

  defp tail(out), do: String.slice(out, max(String.length(out) - 1500, 0), 1500)

  defp script,
    do:
      Application.get_env(:server, :run_task_script) ||
        Path.join(Server.Profiles.tlon_root(), "scripts/workline-verify.sh")
end
