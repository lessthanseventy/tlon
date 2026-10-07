defmodule Server.WorklineDocsTest do
  # What a workline wrote, for the operator to read: its docs from its branch (where its leads commit
  # them), else from the main checkout; "current" is the doc its stage is about.
  use ExUnit.Case, async: false

  alias Server.Thread
  alias Server.Workline.Docs

  setup do
    root = Path.join(System.tmp_dir!(), "workline-docs-#{System.pid()}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    git = fn args ->
      System.cmd("git", ["-C", root, "-c", "user.email=t@t", "-c", "user.name=t" | args], stderr_to_stdout: true)
    end

    {_, 0} = git.(["init", "-q", "-b", "main"])
    File.mkdir_p!(Path.join(root, "work/docs-test"))
    File.write!(Path.join(root, "work/docs-test/intent.md"), "# the ask\n")
    {_, 0} = git.(["add", "work"])
    {_, 0} = git.(["commit", "-qm", "intent on main"])
    {_, 0} = git.(["checkout", "-qb", "work/docs-test"])
    File.write!(Path.join(root, "work/docs-test/spec.md"), "# the spec\n")
    {_, 0} = git.(["add", "work"])
    {_, 0} = git.(["commit", "-qm", "spec on the branch"])
    {_, 0} = git.(["checkout", "-q", "main"])

    previous = Application.get_env(:server, :workline_root)
    Application.put_env(:server, :workline_root, root)

    on_exit(fn ->
      Application.put_env(:server, :workline_root, previous)
      File.rm_rf!(root)
    end)

    :ok
  end

  defp thread(stage), do: struct!(Thread, %{id: 9, title: "t", slug: "docs-test", stage: stage})

  test "lists the workline's docs from its branch and the main checkout" do
    assert Enum.sort(Docs.list(thread("spec"))) == ["intent.md", "spec.md"]
  end

  test "reads a doc by name, wherever it was committed" do
    assert {:ok, "# the spec\n"} = Docs.read(thread("spec"), "spec.md")
    assert {:ok, "# the ask\n"} = Docs.read(thread("spec"), "intent.md")
    assert {:error, _} = Docs.read(thread("spec"), "plan.md")
  end

  test "current is the doc the stage is about" do
    assert {:ok, "# the spec\n"} = Docs.read(thread("spec"), "current")
    assert {:ok, "# the ask\n"} = Docs.read(thread("intent"), "current")
  end

  test "a name outside the workline's docs is refused" do
    assert {:error, _} = Docs.read(thread("spec"), "../../etc/passwd")
  end
end
