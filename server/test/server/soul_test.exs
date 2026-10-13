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
end
