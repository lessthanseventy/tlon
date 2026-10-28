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

    # its own formatter root, so a stray .formatter.exs above the temp dir (/tmp) can't reach the test
    File.write!(Path.join(wt, ".formatter.exs"), "[]\n")

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
    # one clause takes its edit whatever head is named; with two, a head matching neither is refused
    assert {:ok, _} = Tools.clause(t, :insert_after, "demo.ex", "old_name/1", "x", "def old_name(:z), do: :z")
    assert {:error, msg} = Tools.clause(t, :replace, "demo.ex", "old_name/1", "zzz", "1")
    assert msg =~ "have:"
  end

  test "a body-only replace on a clause with a multi-line body lands through the tool path (#442)", %{thread: t, wt: wt} do
    File.write!(Path.join(wt, "needs.ex"), """
    defmodule Needs do
      defp tool_denied(open, listed) do
        for t <- open, not MapSet.member?(listed, t.id) do
          t
        end
      end
    end
    """)

    body = ~S"""
    for t <- open,
        not MapSet.member?(listed, t.id),
        denials = denials_since(t, last_moved(t, nil)),
        length(denials) >= 2,
        not on_duty?(t) do
      last = hd(denials)

      item("tool_denied", "blocking", t, tool_denied_text(t, denials), last.created_at)
    end
    """

    assert {:ok, %{file: "needs.ex"}} = Tools.clause(t, :replace, "needs.ex", "tool_denied/2", "open, listed", body)
    assert File.read!(Path.join(wt, "needs.ex")) =~ ~s|item("tool_denied", "blocking"|
  end

  test "run verbs execute in the worktree and answer one structured result", %{thread: t} do
    # format works on any file (the demo is already formatted → nothing changed)
    assert {:ok, %{ok: true, changed: []}} = Tools.run(t, :format, ["demo.ex"])
  end

  describe "run verbs find the mix project" do
    test "default is the one subdirectory holding a mix.exs; `in` picks one explicitly", %{thread: t, wt: wt} do
      mix_app(wt, "server")
      assert {:ok, %{ok: true}} = Tools.run(t, :compile, [])
      assert {:ok, %{ok: true}} = Tools.run(t, :compile, [], in: "server")
    end

    test "the worktree root wins when it holds a mix.exs", %{thread: t, wt: wt} do
      mix_app(wt, ".")
      assert {:ok, %{ok: true}} = Tools.run(t, :compile, [])
    end

    test "no candidate, or several, is a refusal that names them", %{thread: t, wt: wt} do
      assert {:error, none} = Tools.run(t, :compile, [])
      assert none =~ "no mix.exs"
      mix_app(wt, "server")
      mix_app(wt, "other")
      assert {:error, many} = Tools.run(t, :compile, [])
      assert many =~ "other" and many =~ "server" and many =~ "in:"
    end

    test "`in: \".\"` is the worktree root itself", %{thread: t, wt: wt} do
      mix_app(wt, ".")
      assert {:ok, %{ok: true}} = Tools.run(t, :compile, [], in: ".")
    end

    test "`in` naming a directory that does not exist is refused, not passed on", %{thread: t, wt: wt} do
      mix_app(wt, "server")
      assert {:error, msg} = Tools.run(t, :compile, [], in: "nope")
      assert msg =~ "nope"
    end

    test "`in` outside the worktree is refused", %{thread: t} do
      assert {:error, msg} = Tools.run(t, :compile, [], in: "../..")
      assert msg =~ "outside"
    end
  end

  defp mix_app(wt, dir) do
    app = Path.join(wt, dir)
    File.mkdir_p!(Path.join(app, "lib"))

    File.write!(
      Path.join(app, "mix.exs"),
      "defmodule Tmp#{System.unique_integer([:positive])}.MixProject do\n  use Mix.Project\n  def project, do: [app: :tmp_app, version: \"0.1.0\"]\nend\n"
    )
  end
end
