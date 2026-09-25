defmodule Server.Import.MemoryTest do
  # Claude Code memory files (frontmatter + body) → facts on a project, via its memory thread.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Fact
  alias Server.Import.Memory
  alias Server.Projects
  alias Server.Repo
  alias Server.Thread
  alias Server.Workspaces

  setup do
    Server.TestDB.clean!()
    dir = Path.join(System.tmp_dir!(), "memory-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, ws} = Workspaces.register(%{name: "Home"})
    {:ok, tlon} = Projects.register(%{workspace_id: ws.id, name: "tlon", repos: []})
    {:ok, tlon: tlon, dir: dir}
  end

  defp memory(dir, name, type, body) do
    path = Path.join(dir, name <> ".md")

    File.write!(path, """
    ---
    name: #{name}
    description: the #{name} rule in one line
    metadata:
      type: #{type}
    ---

    #{body}
    """)

    path
  end

  test "an old-style memory with no frontmatter is still knowledge; an index of links is not", ctx do
    dir = Path.join(ctx.dir, "-home-andrew-projects-deuce-seven/memory")
    File.mkdir_p!(dir)
    notes = Path.join(dir, "MEMORY.md")
    File.write!(notes, "# Deuce Seven - Trading Bot\n\n## Project Structure\n- Elixir umbrella app, four apps\n")
    index = Path.join(ctx.dir, "MEMORY.md")
    File.write!(index, "# Memory index\n\n- [Fix or file](fix-or-file.md) — never note\n- [Store](store.md) — postgres\n")

    assert {:ok, %{banked: 1}} = Memory.import_files([notes, index], ctx.tlon)

    fact = Repo.get_by!(Fact, intent: "memory:-home-andrew-projects-deuce-seven/MEMORY")
    assert %{kind: "learned"} = fact
    assert fact.text =~ "Elixir umbrella app"
  end

  test "a memory file becomes a derived fact on the project's closed memory thread", ctx do
    path = memory(ctx.dir, "fix-or-file", "feedback", "Fix it now, or file it.")
    other = memory(ctx.dir, "store-is-postgres", "project", "The store is Postgres.")

    assert {:ok, %{banked: 2, updated: 0}} = Memory.import_files([path, other], ctx.tlon)

    thread = Repo.one!(from t in Thread, where: t.project_id == ^ctx.tlon.id)
    assert %{title: "Claude Code memory", state: "closed"} = thread

    rule = Repo.get_by!(Fact, intent: "memory:fix-or-file")
    assert %{kind: "constraint", provenance: "derived", thread_id: tid} = rule
    assert tid == thread.id
    assert rule.text =~ "the fix-or-file rule in one line"
    assert rule.text =~ "Fix it now, or file it."
    assert Repo.get_by!(Fact, intent: "memory:store-is-postgres").kind == "learned"
  end

  test "a re-import banks nothing twice and carries an edited file's new text", ctx do
    path = memory(ctx.dir, "fix-or-file", "feedback", "Fix it now, or file it.")
    assert {:ok, %{banked: 1}} = Memory.import_files([path], ctx.tlon)

    memory(ctx.dir, "fix-or-file", "feedback", "Fix it now, or file it. Reproduce with a test first.")
    assert {:ok, %{banked: 0, updated: 1}} = Memory.import_files([path], ctx.tlon)
    assert {:ok, %{banked: 0, updated: 0}} = Memory.import_files([path], ctx.tlon)

    assert [fact] = Repo.all(from f in Fact, where: f.intent == "memory:fix-or-file")
    assert fact.text =~ "Reproduce with a test first."
    assert Repo.aggregate(Thread, :count) == 1
  end
end
