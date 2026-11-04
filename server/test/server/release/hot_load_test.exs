defmodule Server.Release.HotLoadTest do
  # The swap, on the real code server: beams compiled here and written to a throwaway directory
  # stand in for the build, and a throwaway repo for the commits.
  use ExUnit.Case, async: false

  alias Server.Release.HotLoad

  setup do
    dir = Path.join(System.tmp_dir!(), "hot-load-#{System.pid()}-#{System.unique_integer([:positive])}")
    ebin = Path.join(dir, "ebin")
    consolidated = Path.join(dir, "consolidated")
    File.mkdir_p!(ebin)
    File.mkdir_p!(consolidated)

    repo = Path.join(dir, "repo")
    File.mkdir_p!(Path.join(repo, "server/lib"))
    git!(repo, ["init", "-q"])
    git!(repo, ["config", "user.email", "t@t"])
    git!(repo, ["config", "user.name", "t"])
    from = commit!(repo, "server/lib/a.ex", "one")
    to = commit!(repo, "server/lib/a.ex", "two")

    module = Module.concat(__MODULE__, "M#{System.unique_integer([:positive])}")
    conflict = Code.get_compiler_option(:ignore_module_conflict)
    Code.put_compiler_option(:ignore_module_conflict, true)

    on_exit(fn ->
      Code.put_compiler_option(:ignore_module_conflict, conflict)
      File.rm_rf!(dir)
    end)

    opts = [root: repo, ebin: ebin, consolidated: consolidated]
    %{ebin: ebin, consolidated: consolidated, repo: repo, from: from, to: to, module: module, opts: opts}
  end

  defp git!(repo, args) do
    {out, 0} = System.cmd("git", ["-C", repo | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp commit!(repo, file, text) do
    File.mkdir_p!(Path.dirname(Path.join(repo, file)))
    File.write!(Path.join(repo, file), text)
    git!(repo, ["add", file])
    git!(repo, ["commit", "-qm", "change"])
    git!(repo, ["rev-parse", "HEAD"])
  end

  defp source(module, version, extra \\ "") do
    """
    defmodule #{inspect(module)} do
      #{extra}
      def version, do: #{version}
      def wait(parent) do
        send(parent, :waiting)
        receive do: (:stop -> :stopped)
      end
    end
    """
  end

  # compiling loads it, so the build's beam is compiled first and the running version after
  defp binary(source) do
    [{_, binary}] = Code.compile_string(source)
    binary
  end

  defp built!(ctx, module, source) do
    File.write!(Path.join(ctx.ebin, "#{module}.beam"), binary(source))
  end

  defp running!(module, source) do
    binary(source)
    :code.purge(module)
  end

  defp run(ctx), do: HotLoad.run(ctx.from, ctx.to, ctx.opts)

  test "a changed module is swapped in", %{module: m} = ctx do
    built!(ctx, m, source(m, 2))
    running!(m, source(m, 1))
    assert m.version() == 1

    assert {:ok, [^m]} = run(ctx)
    assert m.version() == 2
  end

  test "the same beams swap nothing", %{module: m} = ctx do
    built!(ctx, m, source(m, 1))
    assert m.version() == 1

    assert {:ok, []} = run(ctx)
  end

  test "a new module is loaded", %{module: m} = ctx do
    built!(ctx, m, source(m, 1))
    :code.delete(m)
    :code.purge(m)

    assert {:ok, [^m]} = run(ctx)
    assert m.version() == 1
  end

  test "several modules swap together, or none do", %{module: m} = ctx do
    other = Module.concat(m, "Other")
    built!(ctx, m, source(m, 2))
    built!(ctx, other, source(other, 2, "@on_load :go\ndef go, do: :ok"))
    running!(m, source(m, 1))
    running!(other, source(other, 1))

    assert {:restart, why} = run(ctx)
    assert why =~ "refused"
    assert m.version() == 1
    assert other.version() == 1
  end

  test "a changed GenServer means a restart", %{module: m} = ctx do
    built!(ctx, m, source(m, 2, "use GenServer\ndef init(s), do: {:ok, s}"))
    running!(m, source(m, 1))

    assert {:restart, why} = run(ctx)
    assert why =~ inspect(m)
    assert m.version() == 1
  end

  test "a process on the previous version is never killed: it means a restart", %{module: m} = ctx do
    # compiled up front: compiling a module purges its old version, which would kill the process
    third = binary(source(m, 3))
    built!(ctx, m, source(m, 2))
    running!(m, source(m, 1))
    me = self()
    pid = spawn(fn -> m.wait(me) end)
    assert_receive :waiting

    assert {:ok, [^m]} = run(ctx)
    assert m.version() == 2

    File.write!(Path.join(ctx.ebin, "#{m}.beam"), third)

    assert {:restart, why} = run(ctx)
    assert why =~ "still runs"
    assert Process.alive?(pid)
    assert m.version() == 2
    send(pid, :stop)
  end

  test "a removed module means a restart", %{module: m} = ctx do
    path = Path.join(ctx.ebin, "#{m}.beam")
    File.write!(path, binary(source(m, 1)))
    :code.purge(m)
    {:module, ^m} = :code.load_abs(String.to_charlist(Path.rootname(path)))
    File.rm!(path)

    assert {:restart, why} = run(ctx)
    assert why =~ "removed"
  end

  test "a changed consolidated protocol means a restart", %{module: m} = ctx do
    File.write!(Path.join(ctx.consolidated, "#{m}.beam"), binary(source(m, 2)))
    running!(m, source(m, 1))

    assert {:restart, why} = run(ctx)
    assert why =~ "protocol"
    assert m.version() == 1
  end

  for path <- ["server/priv/repo/migrations/1_add.exs", "server/config/runtime.exs", "server/mix.lock", "mise.toml"] do
    test "a change to #{path} means a restart", %{module: m} = ctx do
      built!(ctx, m, source(m, 2))
      running!(m, source(m, 1))
      to = commit!(ctx.repo, unquote(path), "changed")

      assert {:restart, why} = HotLoad.run(ctx.from, to, ctx.opts)
      assert why =~ unquote(path)
      assert m.version() == 1
    end
  end

  test "commits it can't compare mean a restart", ctx do
    assert {:restart, _} = HotLoad.run(nil, ctx.to, ctx.opts)
    assert {:restart, _} = HotLoad.run("0000000", ctx.to, ctx.opts)
  end
end
