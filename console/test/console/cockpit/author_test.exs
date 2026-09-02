defmodule Console.Cockpit.AuthorTest do
  @moduledoc """
  The pure halves of the authoring verbs: menu geometry, key handling over an in-memory menu, the
  changeset sentence. The Server.Workspaces writes are `Console.CockpitWorkspacesTest`.
  """
  use ExUnit.Case, async: true

  alias Console.Cockpit.Author
  alias Console.Panel

  @ws %{id: 3, name: "Freedonia"}

  describe "menu_placements/3 — the overlay, clamped on screen" do
    test "a border + the menu inset, anchored at the click cell" do
      menu = Author.workspace_menu(@ws, 10, 4)
      [{Panel.Border, border, rect}, {Panel.Menu, ^menu, inset}] = Author.menu_placements(menu, 80, 24)

      assert border.title == "Freedonia"
      assert {rect.x, rect.y} == {10, 4}
      # three items + the frame; the content sits two cells in and one down
      assert rect.h == 5
      assert inset == %{x: 12, y: 5, w: rect.w - 4, h: 3}
    end

    test "a menu near the edge is pulled back inside the frame" do
      menu = Author.workspace_menu(@ws, 79, 23)
      [{Panel.Border, _, rect}, _] = Author.menu_placements(menu, 80, 24)
      assert rect.x + rect.w <= 80
      assert rect.y + rect.h <= 24
    end

    test "no menu, no placements" do
      assert Author.menu_placements(nil, 80, 24) == []
    end
  end

  describe "handle_menu_key/2" do
    setup do
      %{state: %{menu: Author.workspace_menu(@ws, 1, 1), active_key: 3, orbis_face: :survey}}
    end

    test "j/k wrap the cursor round the items", %{state: state} do
      assert %{menu: %{cursor: 1}} = Author.handle_menu_key(%{key: :char, char: "j"}, state)
      assert %{menu: %{cursor: 2}} = Author.handle_menu_key(%{key: :char, char: "k"}, state)
      assert %{menu: %{cursor: 1}} = Author.handle_menu_key(%{key: :down}, state)
    end

    test "Esc closes; an unbound key is swallowed without a repaint", %{state: state} do
      assert %{menu: nil} = Author.handle_menu_key(%{key: :escape}, state)
      assert Author.handle_menu_key(%{key: :char, char: "x"}, state) == :ignore
    end

    test "Enter on Configure lands on the author face; on Delete arms the confirm menu", %{state: state} do
      configure = put_in(state.menu.cursor, 1)
      assert %{menu: nil, active_key: :orbis, orbis_face: :author} = Author.handle_menu_key(%{key: :enter}, configure)

      delete = put_in(state.menu.cursor, 2)
      assert %{menu: %{title: "delete?", cursor: 1}} = Author.handle_menu_key(%{key: :enter}, delete)
    end
  end

  describe "changeset_error/1" do
    test "reads as `field message; field message`" do
      cs =
        {%{}, %{name: :string, type: :string}}
        |> Ecto.Changeset.cast(%{}, [:name, :type])
        |> Ecto.Changeset.add_error(:name, "has already been taken")
        |> Ecto.Changeset.add_error(:type, "is invalid")

      assert Author.changeset_error(cs) == "name has already been taken; type is invalid"
    end
  end

  # D2.1: `a`/Esc land `{:toggle_orbis_face}`; `toggle_orbis_face/1` is the pure flip the effect
  # runs — exposed so it's testable without a live GenServer.
  describe "toggle_orbis_face/1: Orbis' survey↔author flip" do
    test "flips :survey to :author" do
      assert %{orbis_face: :author} = Author.toggle_orbis_face(%{orbis_face: :survey})
    end

    test "flips :author back to :survey" do
      assert %{orbis_face: :survey} = Author.toggle_orbis_face(%{orbis_face: :author})
    end
  end
end
