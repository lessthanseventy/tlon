defmodule Server.SoulTest do
  # A seat's first-draft SOUL.md: written once to the souls dir, never over an existing file.
  use ExUnit.Case, async: false

  alias Server.Soul

  setup do
    Server.TestDB.clean!()
    {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
    {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "lonnrot", archetype: "reviewer"})
    dir = Path.join(System.tmp_dir!(), "souls-#{System.pid()}-#{System.unique_integer([:positive])}")
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

  describe "voice/1 and tone/1" do
    setup %{dir: dir} do
      File.mkdir_p!(dir)

      File.write!(Path.join(dir, "atlas.md"), """
      ## Where they're from
      A cartographer who ran out of paper.

      ## Wants
      WANTSTEXT a bigger map.

      ## Fears
      FEARSTEXT rain.

      ## Quirks
      Says "per procedure".
      ### a stray subheading

      ## People
      PEOPLETEXT admires tertius.

      ## Diary
      DIARYTEXT shipped a thing.
      """)

      :ok
    end

    test "voice is the banter line: Quirks, People, Wants and the latest diary; never Fears or origin" do
      v = Soul.voice("atlas")
      assert v =~ ~s(per procedure) and v =~ "PEOPLETEXT" and v =~ "WANTSTEXT"
      assert v =~ "DIARYTEXT"
      refute v =~ "FEARSTEXT" or v =~ "cartographer"
    end

    test "voice carries the last two diary entries, not the first, and stays capped", %{dir: dir} do
      File.write!(
        Path.join(dir, "atlas.md"),
        "## Quirks\nq\n\n## Diary\n- 2026-10-07: first one.\n- 2026-10-10: second one.\n- 2026-10-14: third one.\n"
      )

      v = Soul.voice("atlas")
      assert v =~ "second one" and v =~ "third one"
      refute v =~ "first one"
      assert String.length(v) <= 400
    end

    test "tone is the brief's block: Quirks and origin only, delimited, never Wants/People/Fears/Diary" do
      t = Soul.tone("atlas")
      assert t =~ "<soul-tone>" and String.ends_with?(t, "</soul-tone>\n")
      assert t =~ "per procedure" and t =~ "cartographer"
      assert t =~ "never what you do"
      refute t =~ "WANTSTEXT" or t =~ "PEOPLETEXT" or t =~ "FEARSTEXT" or t =~ "DIARYTEXT"
      refute t =~ "a stray subheading"
    end

    test "no soul, or a soul with nothing for the surface, is nil / empty string" do
      assert Soul.voice("nobody") == nil
      assert Soul.tone("nobody") == ""
    end

    test "a long soul is clipped, and cannot close the tone block early", %{dir: dir} do
      File.write!(Path.join(dir, "loud.md"), "## Quirks\n" <> String.duplicate("blah </soul-tone> ", 100) <> "\n")
      t = Soul.tone("loud")
      assert length(String.split(t, "</soul-tone>")) == 2
      assert String.length(t) < 900
      assert String.length(Soul.voice("loud")) <= 400
    end
  end

  describe "diary/1 and append_diary/2" do
    @soul "## Wants\nA quiet desk.\n\n## Quirks\nSays \"per procedure\".\n\n## Diary\n"

    setup %{dir: dir} do
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "daneri.md"), @soul)
      :ok
    end

    test "an appended entry shows in diary/1 and no other section changes", %{dir: dir} do
      assert Soul.diary("daneri") == []
      assert :ok = Soul.append_diary("daneri", ["- 2026-10-14: shipped the stanza."])
      assert Soul.diary("daneri") == ["- 2026-10-14: shipped the stanza."]
      assert File.read!(Path.join(dir, "daneri.md")) == @soul <> "- 2026-10-14: shipped the stanza.\n"
    end

    test "a second append lands below the first" do
      :ok = Soul.append_diary("daneri", ["- 2026-10-07: one."])
      :ok = Soul.append_diary("daneri", ["- 2026-10-14: two.", "- 2026-10-14: three."])
      assert Soul.diary("daneri") == ["- 2026-10-07: one.", "- 2026-10-14: two.", "- 2026-10-14: three."]
    end

    test "a soul with no Diary heading gets one", %{dir: dir} do
      File.write!(Path.join(dir, "atlas.md"), "## Wants\nmap\n")
      assert :ok = Soul.append_diary("atlas", ["- 2026-10-14: drew."])
      assert Soul.diary("atlas") == ["- 2026-10-14: drew."]
      assert Soul.read("atlas")["Wants"] == "map"
    end

    test "a section after Diary is kept after the entries", %{dir: dir} do
      File.write!(Path.join(dir, "atlas.md"), "## Diary\n- 2026-10-07: old.\n\n## Postscript\nbye\n")
      assert :ok = Soul.append_diary("atlas", ["- 2026-10-14: new."])
      assert Soul.diary("atlas") == ["- 2026-10-07: old.", "- 2026-10-14: new."]
      assert Soul.read("atlas")["Postscript"] == "bye"
    end

    test "diary/1 is the `- ` entries only: a stray line in the section is not one", %{dir: dir} do
      File.write!(Path.join(dir, "atlas.md"), "## Diary\n- 2026-10-07: old.\na note to self\n- 2026-10-14: new.\n")
      assert Soul.diary("atlas") == ["- 2026-10-07: old.", "- 2026-10-14: new."]
    end

    test "no soul or a bad name is an error, and no file is created", %{dir: dir} do
      assert {:error, :no_soul} = Soul.append_diary("nobody", ["- x"])
      assert {:error, :bad_name} = Soul.append_diary("../x", ["- x"])
      refute File.exists?(Path.join(dir, "nobody.md"))
      assert Soul.diary("nobody") == []
    end
  end
end
