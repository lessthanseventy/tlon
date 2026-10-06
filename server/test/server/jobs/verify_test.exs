defmodule Server.Jobs.VerifyTest do
  # A workline entering `verify` queues the deterministic verifier on the service — nothing else
  # has to be watching for the flip.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Workline

  defmodule AllPresent do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, _requirement), do: {:ok, "committed"}
  end

  setup do
    Server.TestDB.clean!()
    start_supervised!({Oban, Application.fetch_env!(:server, Oban)})
    :ok
  end

  test "build → verify enqueues the verifier for that workline; other flips don't" do
    {:ok, t} = Workline.open(%{title: "clock", slug: "clock-fix", stage: "plan"})
    {:ok, at_build} = Workline.advance(t, artifacts: AllPresent)
    refute_enqueued(worker: Server.Jobs.Verify)

    {:ok, at_verify} = Workline.advance(at_build, artifacts: AllPresent)
    assert at_verify.stage == "verify"
    assert_enqueued(worker: Server.Jobs.Verify, args: %{thread_id: t.id, slug: "clock-fix"})
  end
end
