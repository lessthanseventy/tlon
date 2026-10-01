defmodule Server.Workline.ProofTest do
  # The proof a workline carries into its merge gate, read at gate time from git and the event
  # log: the owed artifacts, the verify checks, the branch's diff. A throwaway repo, never this one.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Dossier
  alias Server.Message
  alias Server.Repo
  alias Server.Thread
  alias Server.Workline

  defmodule OnlyReview do
    @moduledoc false
    @behaviour Server.Workline.Artifacts

    @impl true
    def check(_thread, {:file, "review.md"}), do: {:ok, "committed review.md"}
    def check(_thread, requirement), do: {:error, "missing #{inspect(requirement)}"}
  end

  setup do
    Server.TestDB.clean!()
    tmp = Path.join(System.tmp_dir!(), "tlon-proof-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    git = fn args -> {_, 0} = System.cmd("git", ["-C", tmp | args], stderr_to_stdout: true) end
    git.(["init", "-q", "-b", "main"])
    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "root"])

    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, tmp)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(tmp)
    end)

    %{tmp: tmp, git: git}
  end

  defp commit(%{tmp: tmp, git: git}, files, msg) do
    for {path, body} <- files do
      File.mkdir_p!(Path.dirname(Path.join(tmp, path)))
      File.write!(Path.join(tmp, path), body)
      git.(["add", path])
    end

    git.(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", msg])
  end

  test "proof/1: artifacts in the checker's words, newest verify check per command, the branch diff", ctx do
    {:ok, t} = Workline.open(%{title: "wrap", slug: "wrap", stage: "review"})
    commit(ctx, [{"work/wrap/intent.md", "i"}, {"work/wrap/review.md", "r"}], "docs")
    ctx.git.(["checkout", "-q", "-b", "work/wrap"])
    commit(ctx, [{"lib/a.ex", "a\nb\n"}, {"lib/b.ex", "c\n"}], "build")
    ctx.git.(["checkout", "-q", "main"])

    corr = "workline:wrap:verify"
    {:ok, _} = Dossier.record_check(%{thread_id: t.id, cmd: "mix test", exit: 1, correlation: corr})
    {:ok, _} = Dossier.record_check(%{thread_id: t.id, cmd: "mix test", exit: 0, correlation: corr})
    {:ok, _} = Dossier.record_check(%{thread_id: t.id, cmd: "mise run check", exit: 0, correlation: corr})
    {:ok, _} = Dossier.record_check(%{thread_id: t.id, cmd: "elsewhere", exit: 0, correlation: "fact:1"})

    proof = Workline.proof(t)

    assert {"intent", {:ok, _}} = List.keyfind(proof.artifacts, "intent", 0)
    assert {"plan", {:error, why}} = List.keyfind(proof.artifacts, "plan", 0)
    assert why =~ "plan.md is not committed"
    assert {"build", {:ok, "work/wrap @ " <> _}} = List.keyfind(proof.artifacts, "build", 0)
    refute List.keyfind(proof.artifacts, "verify", 0)

    assert Enum.map(proof.checks, &{&1.cmd, &1.exit}) == [{"mise run check", 0}, {"mix test", 0}]
    assert {:ok, diff} = proof.diff
    assert diff =~ "2 files changed"
  end

  test "parking at the review gate posts the proof; a missing branch is said, not hidden" do
    {:ok, t} = Workline.open(%{title: "wrap", slug: "nobranch", stage: "review"})
    {:awaiting, _} = Workline.advance(Repo.get!(Thread, t.id), artifacts: OnlyReview)

    [notice] =
      Repo.all(from m in Message, where: m.thread_id == ^t.id and like(m.body, "⏸%"), select: m.body)

    assert notice =~ "approve #{t.id}"
    assert notice =~ "Proof"
    assert notice =~ "✗ plan"
    assert notice =~ "no verify checks recorded"
    assert notice =~ "diff: "
    assert notice =~ "work/nobranch"
  end
end
