defmodule Server.Office.PetsTest do
  # The pets' voices: a batch of lines per occasion, written in each pet's personality by the cheap
  # tier while an office watches — the whole path with a stand-in model CLI.
  use ExUnit.Case, async: false

  alias Server.Office.Pets

  describe "voices/1" do
    setup do
      Server.TestDB.clean!()
      {:ok, ws} = Server.Workspaces.register(%{name: "Machine"})
      {:ok, _} = Server.Workspaces.seat(ws.id, %{name: "hronir", archetype: "builder"})

      dir = Path.join(System.tmp_dir!(), "pets-#{System.pid()}-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      cli = Path.join(dir, "model")
      calls = Path.join(dir, "calls")

      File.write!(cli, """
      #!/bin/sh
      echo x >> #{calls}
      echo '{"lines": {"pet": ["Adore me, peasant."], "muse": ["Sparkle check.", "  "], "zzz": ["no such occasion"]}}'
      """)

      File.chmod!(cli, 0o755)
      Application.put_env(:server, :banter_cmd, cli)

      on_exit(fn ->
        Application.delete_env(:server, :banter_cmd)
        File.rm_rf!(dir)
      end)

      start_supervised!(Pets)
      %{ws: ws, calls: calls}
    end

    test "a poll asks each pet for its lines, a later poll has them, and the cadence holds", %{ws: ws, calls: calls} do
      assert Pets.voices(ws.id) == %{}

      voices =
        Enum.find_value(1..50, fn _ ->
          Process.sleep(50)
          v = Pets.voices(ws.id)
          map_size(v) == 2 && v
        end)

      assert voices["Nina"] == %{"pet" => ["Adore me, peasant."], "muse" => ["Sparkle check."]}
      # Argos has no "pet" occasion (his is "pat"): only what is his is kept
      assert voices["Argos"] == %{"muse" => ["Sparkle check."]}
      assert File.read!(calls) == "x\nx\n"
    end

    test "with the pets' voices off there is nothing, and nothing is asked", %{ws: ws} do
      stop_supervised!(Pets)
      assert Pets.voices(ws.id) == %{}
    end
  end

  test "each pet is asked in its own personality, about this office" do
    ctx = %{crew: [%{name: "hronir", archetype: "builder", lead: true, thread: nil}], tickets: []}
    nina = Pets.prompt("Nina", ctx)
    assert nina =~ "princess" and nina =~ "hronir" and nina =~ ~s("fuss_treat")
    assert nina =~ ~s(a coworker is "they")
    refute nina =~ ~s("belly":)
    assert Pets.prompt("Argos", ctx) =~ "Homer"
    assert Pets.prompt("Argos", ctx) =~ ~s("rally") and nina =~ ~s("shipped")
  end

  test "a reply keeps only the pet's occasions, as trimmed, short, non-empty lines" do
    assert Pets.parse(~s(x {"lines": {"pet": [" hi ", "", 3], "nope": ["x"]}}), "Nina") == %{"pet" => ["hi"]}
    assert Pets.parse("no json", "Nina") == nil
  end
end
