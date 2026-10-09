defmodule Server.Recall.RecheckTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Event
  alias Server.Recall.Recheck
  alias Server.Recall.Strength
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    repo = Path.join(System.tmp_dir!(), "recheck-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(repo, "server/lib"))
    File.write!(Path.join(repo, "server/lib/a.ex"), "defmodule Server.A do\nend\n")
    git = fn args -> {_, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    git.(["init", "-q"])
    git.(["add", "."])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x"])
    git.(["update-ref", "refs/remotes/origin/main", "HEAD"])
    on_exit(fn -> File.rm_rf!(repo) end)

    {:ok, ws} = Server.Workspaces.register(%{name: "W"})
    {:ok, project} = Server.Projects.register(%{workspace_id: ws.id, name: "p", repos: [%{"name" => "t", "path" => repo}]})
    {:ok, thread} = Channel.open_thread(%{title: "t", workspace_id: ws.id, project_id: project.id})
    %{thread: thread}
  end

  defp fact(thread, text) do
    {:ok, f} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: "derived"})
    f
  end

  defp checks(f), do: Repo.all(from e in Event, where: e.correlation == ^"fact:#{f.id}" and like(e.kind, "check_%"), select: e.kind)

  test "a fact whose refs exist passes", %{thread: t} do
    f = fact(t, "`Server.A` exists in server/lib/a.ex")
    assert {:ok, :passed} = Recheck.run(f)
    assert checks(f) == ["check_passed"]
  end

  test "a fact naming a gone symbol fails, and weighs less", %{thread: t} do
    ok = fact(t, "`Server.A` exists")
    bad = fact(t, "`Server.Gone` does the work")
    {:ok, :passed} = Recheck.run(ok)
    assert {:ok, :failed} = Recheck.run(bad)
    assert checks(bad) == ["check_failed"]
    assert strength(bad) < strength(ok)
  end

  test "prose, and a fact with no thread, are skipped", %{thread: t} do
    prose = fact(t, "Forgetting is asymmetric in cost.")
    assert {:ok, :skipped} = Recheck.run(prose)
    assert checks(prose) == []

    {:ok, loose} = Dossier.bank_fact(%{kind: "learned", text: "`Server.A` exists", provenance: "derived"})
    assert {:ok, :skipped} = Recheck.run(loose)
  end

  test "a second run within 24h is skipped", %{thread: t} do
    f = fact(t, "`Server.A` exists")
    {:ok, :passed} = Recheck.run(f)
    assert {:ok, :skipped} = Recheck.run(f)
    assert checks(f) == ["check_passed"]
  end

  defp strength(f) do
    now = DateTime.utc_now()

    touches =
      Repo.all(
        from e in Event,
          where: e.correlation == ^"fact:#{f.id}" and like(e.kind, "check_%"),
          select: %{kind: e.kind, at: e.created_at}
      )

    Strength.of(Strength.touches_for(%{created_at: f.created_at, touches: touches}, now), now)
  end
end
