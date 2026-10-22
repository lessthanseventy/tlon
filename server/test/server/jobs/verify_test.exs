defmodule Server.Jobs.VerifyTest do
  # A workline entering `verify` queues the deterministic verifier on the service — nothing else
  # has to be watching for the flip.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

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

  test "companions: other verifies waiting in the same repo, first come first, never itself" do
    {:ok, a} = Workline.open(%{title: "a", slug: "comp-a", stage: "verify"})
    {:ok, b} = Workline.open(%{title: "b", slug: "comp-b", stage: "verify"})
    {:ok, c} = Workline.open(%{title: "c", slug: "comp-c", stage: "verify"})
    lead = %{thread_id: a.id, slug: a.slug} |> Server.Jobs.Verify.new() |> Server.Repo.insert!()
    for t <- [b, c], do: %{thread_id: t.id, slug: t.slug} |> Server.Jobs.Verify.new() |> Server.Repo.insert!()

    assert Enum.map(Server.Jobs.Verify.companions(a, lead.id), & &1.id) == [b.id, c.id]
  end

  describe "finish/5 — a run is done when it recorded a result; one killed before that is tried again" do
    setup do
      {:ok, t} = Workline.open(%{title: "lazy", slug: "lazy-compile", stage: "verify"})
      %{t: t}
    end

    defp check!(t, exit) do
      {:ok, e} =
        Server.Dossier.record_check(%{
          thread_id: t.id,
          cmd: "mise run check",
          exit: exit,
          tail: "",
          correlation: "workline:#{t.slug}:verify"
        })

      e
    end

    test "a recorded result, green or red, is the end of it: no retry", %{t: t} do
      for exit <- [0, 1] do
        since = check!(t, 0).id
        check!(t, exit)
        assert :ok = Server.Jobs.Verify.finish(t.id, t.slug, since, {"", exit}, %{attempt: 1, max_attempts: 3})
      end
    end

    test "red goes back to build on the same branch, its builder told what broke; green stays", %{t: t} do
      since = check!(t, 0).id
      check!(t, 0)
      assert :ok = Server.Jobs.Verify.finish(t.id, t.slug, since, {"", 0}, %{attempt: 1, max_attempts: 3})
      assert %{stage: "verify"} = Server.Repo.get!(Server.Thread, t.id)

      since = check!(t, 0).id
      check!(t, 1)
      assert :ok = Server.Jobs.Verify.finish(t.id, t.slug, since, {"", 1}, %{attempt: 1, max_attempts: 3})
      assert %{stage: "build"} = Server.Repo.get!(Server.Thread, t.id)

      assert Enum.any?(
               Server.Repo.all(from m in Server.Message, where: m.thread_id == ^t.id, select: m.body),
               &(&1 =~ "back to build — verify is red: mise run check (exit 1)")
             )
    end

    test "nothing recorded — the run was killed (a restart, a signal) — is an error, so Oban runs it again", %{t: t} do
      since = check!(t, 0).id

      assert {:error, why} =
               Server.Jobs.Verify.finish(t.id, t.slug, since, {"Terminated", 143}, %{attempt: 1, max_attempts: 3})

      assert why =~ "recorded nothing"
    end

    test "a thread closed while it ran is cancelled, not retried or reported", %{t: t} do
      since = check!(t, 0).id
      {:ok, _} = Server.Channel.close_thread(t)

      assert {:cancel, why} =
               Server.Jobs.Verify.finish(t.id, t.slug, since, {"", 1}, %{attempt: 3, max_attempts: 3})

      assert why =~ "closed"
    end

    test "a thread already closed is cancelled before anything runs", %{t: t} do
      {:ok, _} = Server.Channel.close_thread(t)
      n = Server.Repo.aggregate(Server.Message, :count)

      assert {:cancel, _} = perform_job(Server.Jobs.Verify, %{thread_id: t.id, slug: t.slug})
      assert Server.Repo.aggregate(Server.Message, :count) == n
    end

    test "a workline a train already took past verify is cancelled before anything runs", %{t: t} do
      {:ok, _} = t |> Server.Thread.workline_stage_changeset(%{stage: "review"}) |> Server.Repo.update()
      assert {:cancel, why} = perform_job(Server.Jobs.Verify, %{thread_id: t.id, slug: t.slug})
      assert why =~ "review"
    end

    test "the verifier is tried three times, not once" do
      assert %{changes: %{max_attempts: 3}} = Server.Jobs.Verify.new(%{thread_id: 1, slug: "x"})
    end
  end
end
