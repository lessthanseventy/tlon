defmodule Server.Source.ToolsTest do
  # The coworkers' source verbs (Andrew, 2026-09-08: "baked into the coworkers"): rename/outline
  # over FILES, scoped to the calling thread's worktree — a path outside it is refused, so an
  # agent edits its own tree and nothing else. The MCP components are thin callers of this.
  use ExUnit.Case, async: false

  alias Server.Source.Tools

  setup do
    Server.TestDB.clean!()
    %{repo: repo, ws: ws, project: p} = Server.TestRepoDir.with_project()
    {:ok, thread} = Server.Channel.open_thread(%{title: "tools", workspace_id: ws.id, project_id: p.id})
    {:ok, wt} = Server.worktree_for_thread(thread)

    File.write!(
      Path.join(wt, "demo.ex"),
      "defmodule Demo do\n  def old_name(x), do: x\n  def two, do: old_name(1)\nend\n"
    )

    %{repo: repo, thread: thread, wt: wt}
  end

  test "rename patches files inside the thread's worktree and reports which changed", %{thread: t, wt: wt} do
    assert {:ok, %{changed: ["demo.ex"]}} = Tools.rename(t, ["demo.ex"], "old_name", "new_name", [])
    assert File.read!(Path.join(wt, "demo.ex")) =~ "def new_name(x)"
    assert File.read!(Path.join(wt, "demo.ex")) =~ "do: new_name(1)"
  end

  test "a path outside the worktree is refused", %{thread: t} do
    assert {:error, msg} = Tools.rename(t, ["../../etc/passwd"], "a", "b", [])
    assert msg =~ "outside"
    assert {:error, msg2} = Tools.outline(t, "/etc/hostname")
    assert msg2 =~ "outside"
  end

  test "outline returns the file's modules and defs", %{thread: t} do
    assert {:ok, %{file: "demo.ex", modules: [%{module: "Demo", defs: defs}]}} = Tools.outline(t, "demo.ex")
    assert Enum.map(defs, &{&1.name, &1.arity}) == [{:old_name, 1}, {:two, 0}]
  end

  test "a thread with no repo has no tree to work in", %{} do
    {:ok, empty} = Server.Workspaces.register(%{name: "no-repo"})
    {:ok, bare} = Server.Channel.open_thread(%{title: "bare", workspace_id: empty.id})
    assert {:error, msg} = Tools.outline(bare, "x.ex")
    assert msg =~ "no repo"
  end

  test "clause verbs edit one clause inside the worktree", %{thread: t, wt: wt} do
    assert {:ok, %{file: "demo.ex"}} = Tools.clause(t, :replace, "demo.ex", "old_name/1", "x", "x + 1")
    assert File.read!(Path.join(wt, "demo.ex")) =~ "def old_name(x), do: x + 1"
    assert {:ok, _} = Tools.clause(t, :insert_after, "demo.ex", "two/0", "", "def three, do: 3")
    assert File.read!(Path.join(wt, "demo.ex")) =~ "def three, do: 3"
    assert {:ok, _} = Tools.clause(t, :delete, "demo.ex", "three/0", "", nil)
    refute File.read!(Path.join(wt, "demo.ex")) =~ "three"
    assert {:error, msg} = Tools.clause(t, :replace, "demo.ex", "old_name/1", "zzz", "1")
    assert msg =~ "have:"
  end

  test "run verbs execute in the worktree and answer one structured result", %{thread: t, wt: wt} do
    # format works on any file (the demo is already formatted → nothing changed) …
    assert {:ok, %{ok: true, changed: []}} = Tools.run(t, :format, ["demo.ex"])
    # … while compile needs a mix project, which a bare test repo is not: the verb says so, honestly
    assert {:ok, %{ok: false, exit: exit}} = Tools.run(t, :compile, [])
    assert is_integer(exit) and exit != 0
    _ = wt
  end
end
