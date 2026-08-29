defmodule Console.Panel.AuthorTest do
  # AUTHOR — the Orbis author face's editable workspace list (D2.2). Pins the panel → styled-rows path
  # headlessly: one row per workspace with its counts, the cursor row washed :selected, an empty-state
  # placeholder, and the footer hints line.
  use ExUnit.Case, async: true

  alias Console.Panel.Author

  @rect %{x: 0, y: 0, w: 80, h: 100}

  defp lines(rows) do
    Enum.map(rows, fn row -> Enum.map_join(row, fn {t, _style} -> t end) end)
  end

  test "renders the ORBIS · author header, one row per workspace, and the footer hints" do
    data = %{
      workspaces: [
        %{
          id: 1,
          name: "Tlön",
          type: "code",
          paths: ["modules/*"],
          roster: [%{"archetype" => "surveyor"}],
          scope: "machine"
        }
      ],
      cursor: 0
    }

    text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

    assert text =~ "ORBIS · author"
    assert text =~ "Tlön"
    assert text =~ "code"
    assert text =~ "1 paths"
    assert text =~ "1 roster"
    assert text =~ "n new"
    assert text =~ "d delete"
    assert text =~ "a survey"
  end

  test "no workspaces renders the header and a create-hint placeholder, no crash" do
    text = %{workspaces: [], cursor: 0} |> Author.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "ORBIS · author"
    assert text =~ "no workspaces yet"
  end

  test "the cursor row washes :selected; every other row doesn't" do
    data = %{
      workspaces: [
        %{id: 1, name: "Tlön", type: "code", paths: [], roster: []},
        %{id: 2, name: "Freedonia", type: "blank", paths: [], roster: []}
      ],
      cursor: 1
    }

    rows = Author.render(data, @rect)

    freedonia = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Freedonia" end))
    assert Enum.any?(freedonia, fn {_t, s} -> s == :selected end)

    tlon = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "Tlön" end))
    refute Enum.any?(tlon, fn {_t, s} -> s == :selected end)
  end

  test "a missing type/paths/roster degrades gracefully instead of crashing" do
    data = %{workspaces: [%{id: 1, name: "Bare"}], cursor: 0}
    text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")
    assert text =~ "Bare"
    assert text =~ "0 paths"
    assert text =~ "0 roster"
  end

  test "pick/3 is a no-op for now — no editor yet (Chunk 2)" do
    data = %{workspaces: [%{id: 1, name: "Tlön"}], cursor: 0}
    assert Author.pick(data, @rect, 2) == nil
  end

  describe "the field editor sub-view (D2.4 Chunk 2a: data[:edit] present)" do
    @workspace %{
      id: 22,
      name: "Freedonia",
      type: "code",
      scope: "project",
      paths: ["modules/*"],
      roster: [%{"archetype" => "surveyor", "name" => "surveyor"}]
    }

    defp edit_data(edit, overrides \\ %{}) do
      Map.merge(%{workspaces: [@workspace], cursor: 0, edit: edit}, overrides)
    end

    test "renders the workspace's name (immutable, no field for it) and the type/scope/paths/roster rows" do
      data = edit_data(%{id: 22, field: 0, sub: 0, mode: :field})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

      assert text =~ "Freedonia"
      assert text =~ "code"
      assert text =~ "project"
      assert text =~ "1 paths"
      assert text =~ "1 roster"
      assert text =~ "immutable"
    end

    test "the field cursor row washes :selected" do
      data = edit_data(%{id: 22, field: 1, sub: 0, mode: :field})
      rows = Author.render(data, @rect)

      scope_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "project" end))
      assert Enum.any?(scope_row, fn {_t, s} -> s == :selected end)

      type_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "code" end))
      refute Enum.any?(type_row, fn {_t, s} -> s == :selected end)
    end

    test "field-list hints name j/k, h/l, Enter, Esc" do
      data = edit_data(%{id: 22, field: 0, sub: 0, mode: :field})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

      assert text =~ "j/k field"
      assert text =~ "h/l"
      assert text =~ "Enter"
      assert text =~ "Esc"
    end

    test "an editor pointed at a workspace not in the list degrades to the plain list (defensive)" do
      data = edit_data(%{id: 999_999, field: 0, sub: 0, mode: :field})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")
      assert text =~ "ORBIS · author"
      assert text =~ "Freedonia"
    end
  end

  describe "the paths sub-list (D2.4 Chunk 2b: mode: :sub, field: 2)" do
    @workspace_with_paths %{
      id: 22,
      name: "Freedonia",
      type: "code",
      scope: "project",
      paths: ["modules/aleph", "modules/funes"],
      roster: []
    }

    defp sub_data(edit) do
      %{workspaces: [@workspace_with_paths], cursor: 0, edit: edit}
    end

    test "renders one row per path, the sub cursor washed :selected" do
      data = sub_data(%{id: 22, field: 2, sub: 1, mode: :sub})
      rows = Author.render(data, @rect)

      funes_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "modules/funes" end))
      assert Enum.any?(funes_row, fn {_t, s} -> s == :selected end)

      aleph_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t == "modules/aleph" end))
      refute Enum.any?(aleph_row, fn {_t, s} -> s == :selected end)
    end

    test "an empty paths list renders a placeholder, no crash" do
      data = sub_data(%{id: 22, field: 2, sub: 0, mode: :sub})
      data = put_in(data.workspaces, [%{@workspace_with_paths | paths: []}])
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")
      assert text =~ "no paths yet"
    end

    test "sub-list hints name j/k, a add, x/d remove, Esc back" do
      data = sub_data(%{id: 22, field: 2, sub: 0, mode: :sub})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

      assert text =~ "j/k row"
      assert text =~ "a add"
      assert text =~ "x/d remove"
      assert text =~ "Esc back"
    end
  end

  describe "the roster sub-list (D2.4 Chunk 2c: mode: :sub, field: 3)" do
    @workspace_with_roster %{
      id: 22,
      name: "Freedonia",
      type: "code",
      scope: "machine",
      paths: [],
      roster: [%{"archetype" => "surveyor", "name" => "tertius"}, %{"archetype" => "builder", "name" => "hronir"}]
    }

    defp roster_sub_data(edit, overrides \\ %{}) do
      Map.merge(%{workspaces: [@workspace_with_roster], cursor: 0, edit: edit}, overrides)
    end

    test "renders one row per roster entry (archetype · name), the sub cursor washed :selected" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 1, mode: :sub})
      rows = Author.render(data, @rect)

      hronir_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "hronir" end))
      assert Enum.any?(hronir_row, fn {_t, s} -> s == :selected end)
      assert Enum.any?(hronir_row, fn {t, _} -> t =~ "builder" end)

      tertius_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "tertius" end))
      refute Enum.any?(tertius_row, fn {_t, s} -> s == :selected end)
    end

    test "an empty roster renders a placeholder, no crash" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub})
      data = put_in(data.workspaces, [%{@workspace_with_roster | roster: []}])
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")
      assert text =~ "no roster yet"
    end

    test "sub-list hints name j/k, a add, x/d remove, Esc back" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

      assert text =~ "j/k row"
      assert text =~ "a add"
      assert text =~ "x/d remove"
      assert text =~ "Esc back"
    end

    test "roster hints also name Tab knob and Enter apply (D2.4 Chunk 2b)" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

      assert text =~ "Tab knob"
      assert text =~ "Enter apply"
    end

    test "each row shows its effective model (archetype default, no Config override) and yolo/ask" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub})
      text = data |> Author.render(@rect) |> lines() |> Enum.join("\n")

      # surveyor's archetype default model + the unset (no Config override) yolo → "ask"
      assert text =~ "ask"
      assert Regex.match?(~r/tertius.*\w+\/[\w.-]+.*ask/, text)
    end

    test "on the sub-selected row, the ARMED knob (edit.knob) washes :accent; the other stays :dim" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub, knob: :model})
      rows = Author.render(data, @rect)

      tertius_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "tertius" end))
      # find the model run (a provider/model pair) and the yolo run ("ask"/"yolo") by content
      model_run = Enum.find(tertius_row, fn {t, _} -> t =~ "/" end)
      yolo_run = Enum.find(tertius_row, fn {t, _} -> t in ["ask", "yolo"] end)

      assert elem(model_run, 1) == :accent
      assert elem(yolo_run, 1) == :dim
    end

    test "flipping edit.knob to :yolo moves the accent wash to the yolo column" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub, knob: :yolo})
      rows = Author.render(data, @rect)

      tertius_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "tertius" end))
      model_run = Enum.find(tertius_row, fn {t, _} -> t =~ "/" end)
      yolo_run = Enum.find(tertius_row, fn {t, _} -> t in ["ask", "yolo"] end)

      assert elem(model_run, 1) == :dim
      assert elem(yolo_run, 1) == :accent
    end

    test "a non-selected row's knobs are always :dim regardless of edit.knob" do
      data = roster_sub_data(%{id: 22, field: 3, sub: 0, mode: :sub, knob: :model})
      rows = Author.render(data, @rect)

      hronir_row = Enum.find(rows, &Enum.any?(&1, fn {t, _} -> t =~ "hronir" end))
      model_run = Enum.find(hronir_row, fn {t, _} -> t =~ "/" end)
      yolo_run = Enum.find(hronir_row, fn {t, _} -> t in ["ask", "yolo"] end)

      assert elem(model_run, 1) == :dim
      assert elem(yolo_run, 1) == :dim
    end
  end
end
