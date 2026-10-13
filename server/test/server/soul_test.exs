defmodule Server.SoulTest do
  # A seat's first-draft SOUL.md: written once to the souls dir, never over an existing file.
  use ExUnit.Case, async: false

  alias Server.Soul

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})
    dir = Path.join(System.tmp_dir!(), "souls-#{System.unique_integer([:positive])}")
    Application.put_env(:server, :souls_dir, dir)

    on_exit(fn ->
      Application.put_env(:server, :souls_dir, Path.join(System.tmp_dir!(), "tlon-test-souls-unset"))
      File.rm_rf!(dir)
    end)

    %{ws: ws, dir: dir}
  end

  # a stand-in model CLI: prints `reply`, and logs its prompt (`$2`) to `<cli>.prompt`
  defp stub_model(%{dir: dir}, reply) do
    File.mkdir_p!(dir)
    cli = Path.join(dir, "model")
    File.write!(cli, "#!/bin/sh\nprintf '%s' \"$2\" > #{cli}.prompt\ncat <<'EOF'\n#{reply}\nEOF\n")
    File.chmod!(cli, 0o755)
    Application.put_env(:server, :generator_cmd, cli)
    on_exit(fn -> Application.put_env(:server, :generator_cmd, "/nonexistent/tlon-test-generator") end)
    cli
  end

  test "a seat with no soul gets a file with every section heading and an empty Diary", %{ws: ws, dir: dir} do
    assert {:ok, :written} = Soul.draft(ws.id, "lonnrot")
    body = File.read!(Path.join(dir, "lonnrot.md"))

    for h <- ["Where they're from", "Wants", "Fears", "Quirks", "People", "The side project", "Diary"],
        do: assert(body =~ "## #{h}\n")

    assert String.ends_with?(body, "## Diary\n")
  end

  test "an existing soul is never overwritten, edited or not", %{ws: ws, dir: dir} do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "lonnrot.md"), "## Wants\nmine\n")
    assert {:ok, :exists} = Soul.draft(ws.id, "lonnrot")
    assert File.read!(Path.join(dir, "lonnrot.md")) == "## Wants\nmine\n"
  end

  test "a name that is not a seat, or not a safe file name, is refused", %{ws: ws} do
    assert {:error, :no_seat} = Soul.draft(ws.id, "nobody")
    assert {:error, :bad_name} = Soul.draft(ws.id, "../etc/passwd")
  end

  test "the §5 samples are written verbatim with no model call; Scharlach is the Dwight", %{dir: dir} do
    {:ok, ws} = Server.Workspaces.register(%{name: "Other"})
    for n <- ~w(scharlach daneri sonny), do: {:ok, _} = Server.Workspaces.seat(ws.id, %{name: n, archetype: "builder"})
    for n <- ~w(scharlach daneri sonny), do: assert({:ok, :written} = Soul.draft(ws.id, n))
    s = File.read!(Path.join(dir, "scharlach.md"))
    assert s =~ "Assistant to the Manager" and s =~ "WORLD'S BEST SHERIFF" and s =~ "per procedure"
    assert File.read!(Path.join(dir, "daneri.md")) =~ "The Earth"
    assert File.read!(Path.join(dir, "sonny.md")) =~ "daisy"
  end

  test "a seat outside the samples is drafted by the model from its story and voice", ctx do
    cli =
      stub_model(
        ctx,
        "## Where they're from\nFrom the story.\n\n## Wants\nw\n\n## Fears\nf\n\n## Quirks\nq\n\n## People\np\n\n## The side project\ns\n\n## Diary\nINVENTED ENTRY\n"
      )

    assert {:ok, :written} = Soul.draft(ctx.ws.id, "lonnrot")
    body = File.read!(Path.join(ctx.dir, "lonnrot.md"))
    assert body =~ "From the story."
    refute body =~ "INVENTED ENTRY"
    assert String.ends_with?(body, "## Diary\n")
    prompt = File.read!(cli <> ".prompt")
    assert prompt =~ "Death and the Compass" and prompt =~ "a detective"
  end

  test "a malformed model reply falls back to the template", ctx do
    stub_model(ctx, "sorry, no")
    assert {:ok, :written} = Soul.draft(ctx.ws.id, "lonnrot")
    assert File.read!(Path.join(ctx.dir, "lonnrot.md")) =~ "## Fears\n"
  end

  test "draft_all drafts every seat that has none and reports each", %{ws: ws, dir: dir} do
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "yu", archetype: "planner"})
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "yu.md"), "mine")
    assert %{"lonnrot" => {:ok, :written}, "yu" => {:ok, :exists}} = Soul.draft_all(ws.id)
    assert File.read!(Path.join(dir, "yu.md")) == "mine"
  end

  describe "read/1" do
    test "splits a soul file into its sections, trimmed", %{dir: dir} do
      File.mkdir_p!(dir)

      File.write!(
        Path.join(dir, "atlas.md"),
        "## Quirks\nA chipped mug.\n\n## Wants\nA quiet desk.\nA window.\n\n## Diary\n"
      )

      assert %{"Quirks" => "A chipped mug.", "Wants" => "A quiet desk.\nA window.", "Diary" => ""} =
               Soul.read("atlas")
    end

    test "no file, an unreadable name, or text with no headings is no sections, never a raise", %{dir: dir} do
      assert Soul.read("atlas") == nil
      assert Soul.read("../etc/passwd") == nil
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "atlas.md"), "just some text\n")
      assert Soul.read("atlas") == %{}
    end

    test "an unknown heading is kept", %{dir: dir} do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "atlas.md"), "## Hobbies\nknots\n")
      assert %{"Hobbies" => "knots"} = Soul.read("atlas")
    end
  end
end
