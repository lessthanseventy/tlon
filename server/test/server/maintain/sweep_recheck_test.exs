defmodule Server.Maintain.SweepRecheckTest do
  # The sweep rechecks facts that name code (Server.Recall.Recheck): a batch per run, live facts only.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Dossier
  alias Server.Event
  alias Server.Maintain.Sweep
  alias Server.Repo

  setup do
    Server.TestDB.clean!()
    repo = Path.join(System.tmp_dir!(), "sweep-recheck-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(repo, "server/lib"))
    File.write!(Path.join(repo, "server/lib/a.ex"), "defmodule Server.A do\nend\n")
    git = fn args -> {_, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true) end
    git.(["init", "-q"])
    git.(["add", "."])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x"])
    git.(["update-ref", "refs/remotes/origin/main", "HEAD"])
    on_exit(fn -> File.rm_rf!(repo) end)

    {:ok, ws} = Server.Workspaces.register(%{name: "W"})
    {:ok, p} = Server.Projects.register(%{workspace_id: ws.id, name: "p", repos: [%{"name" => "t", "path" => repo}]})
    {:ok, thread} = Channel.open_thread(%{title: "t", workspace_id: ws.id, project_id: p.id})
    %{thread: thread}
  end

  defp fact(thread, text) do
    {:ok, f} = Dossier.bank_fact(%{thread_id: thread.id, kind: "learned", text: text, provenance: "derived"})
    f
  end

  defp kinds, do: from(e in Event, where: like(e.kind, "check_%"), select: e.kind) |> Repo.all() |> Enum.sort()

  test "a stale and a fine fact are rechecked; a forgotten one is not", %{thread: t} do
    fact(t, "`Server.A` exists")
    fact(t, "`Server.Gone` does the work")
    gone = fact(t, "`Server.A` was forgotten")
    Repo.update_all(from(f in Server.Fact, where: f.id == ^gone.id), set: [forgotten_at: DateTime.utc_now()])

    Sweep.run()
    assert kinds() == ["check_failed", "check_passed"]
  end

  test "a run rechecks 25 facts at most", %{thread: t} do
    for i <- 1..30, do: fact(t, "`Server.A` number #{i}")
    Sweep.run()
    assert length(kinds()) == 25
  end
end
