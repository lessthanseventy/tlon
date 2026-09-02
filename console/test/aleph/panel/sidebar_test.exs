defmodule Console.Panel.SidebarTest do
  @moduledoc """
  The thin far-left SPINE (Slice 3.4): chunky icon TILES in three separator-ruled sections —
  numbered workspaces (top), the specials (Home/god-view, Tickets, Notes), and the actions (settings,
  `+`) pinned at the bottom — over `Server.Board.sidebar/0`'s read. A tile IS the space nav (click/Enter
  switches; active fills SOLID, no arrow; `+` creates, the cog configures). Glyphs come from
  `Console.Icons` (Nerd Fonts), referenced here so a codepoint swap doesn't break the tests.
  """
  use ExUnit.Case, async: true

  alias Console.Icons
  alias Console.Panel.Sidebar

  defp text(row), do: Enum.map_join(row, fn {t, _style} -> t end)
  defp texts(rows), do: Enum.map(rows, &text/1)
  # The run-list of the first rendered row whose text contains `substr`, and its style atoms — the
  # active/cursor cue is now a fill STYLE (no arrow glyph), so tests read styles, not text.
  defp row_with(rows, substr), do: Enum.find(rows, fn row -> text(row) =~ substr end)
  defp styles_of(row), do: Enum.map(row || [], fn {_t, s} -> s end)

  @rect %{x: 0, y: 0, w: 40, h: 30}

  defp thread(over) do
    Map.merge(
      %{
        id: 1,
        workspace_id: 1,
        title: "a thread",
        root: false,
        stage: nil,
        awaiting: nil,
        lead: nil,
        working: false,
        last_at: nil
      },
      over
    )
  end

  defp groups do
    [
      %{
        workspace: %{id: 1, name: "ficciones"},
        threads: [
          thread(%{id: 10, title: "general", root: true}),
          thread(%{id: 11, title: "fix the tick crash", working: true, stage: "build", lead: "hronir"}),
          thread(%{id: 12, title: "review pass", stage: "verify", awaiting: "operator"})
        ],
        crew: [
          %{name: "hronir", archetype: "builder", working: true},
          %{name: "tertius", archetype: "surveyor", working: false}
        ]
      },
      %{
        workspace: %{id: 2, name: "sandbox"},
        threads: [],
        crew: []
      }
    ]
  end

  test "workspaces at the top; the tools (Home/Tickets/Notes/settings/+) grouped at the bottom" do
    # Rendered non-kitty (default), so the fallback digits/glyphs show as text and are findable.
    rows = Sidebar.render(%{groups: groups(), active_key: :orbis}, @rect)
    lines = texts(rows)

    at = fn s -> Enum.find_index(lines, &(&1 =~ s)) end

    # Numbered workspaces at the top, in read order (1-based — the super+1..9 mental model).
    assert at.("1") < at.("2")
    # The tools sit BELOW the workspaces, together: Home (god-view), Tickets, Notes, then settings, `+`.
    assert at.("2") < at.(Icons.home())
    assert at.(Icons.home()) < at.(Icons.ticket())
    assert at.(Icons.ticket()) < at.(Icons.note())
    assert at.(Icons.note()) < at.(Icons.settings())
    assert at.(Icons.settings()) < at.(Icons.add())
    # A section rule separates specials from actions.
    assert Enum.any?(lines, &(&1 =~ "───"))

    # No labels, no thread/crew sub-rows (those live in the center thread-stack and the CREW rail).
    refute Enum.any?(lines, &(&1 =~ "ficciones"))
    refute Enum.any?(lines, &(&1 =~ "hronir"))
  end

  test "on a kitty host the fallback glyph/digit is blanked (the icon PNG covers it, no bleed)" do
    plain = %{groups: groups(), active_key: :orbis} |> Sidebar.render(@rect) |> texts()
    kitty = %{groups: groups(), active_key: :orbis, graphics?: true} |> Sidebar.render(@rect) |> texts()

    # Off kitty the digit shows; on kitty it's blanked (only the placed image renders).
    assert Enum.any?(plain, &(&1 =~ "1"))
    refute Enum.any?(kitty, &(&1 =~ "1"))
    refute Enum.any?(kitty, &(&1 =~ Icons.home()))
  end

  test "the active space fills solid (a style cue, no arrow marker)" do
    rows = Sidebar.render(%{groups: groups(), active_key: 2}, @rect)

    # Workspace 2's tile fills (:selected); Home (Orbis) does not; no ▸/→ arrows anywhere.
    assert :selected in styles_of(row_with(rows, "2"))
    refute :selected in styles_of(row_with(rows, Icons.home()))
    refute Enum.any?(texts(rows), &(&1 =~ "▸" or &1 =~ "→"))
  end

  test "the nav cursor accents the tile Enter would switch to (no arrow)" do
    # cursor 0 = Home, 1 = first workspace, 2 = second.
    rows = Sidebar.render(%{groups: groups(), active_key: :orbis, selected: 1}, @rect)
    assert :accent in styles_of(row_with(rows, "1"))
  end

  test "key_at resolves the cursor to a space key: Home then workspace ids" do
    data = %{groups: groups(), active_key: :orbis}
    assert Sidebar.key_at(data, 0) == :orbis
    assert Sidebar.key_at(data, 1) == 1
    assert Sidebar.key_at(data, 2) == 2
    assert Sidebar.key_at(data, 3) == nil
  end

  test "pick: workspaces/Home switch, +/cog act, Tickets/Notes open their board" do
    data = %{groups: groups(), active_key: :orbis}
    tall = %{@rect | h: 200}
    lines = texts(Sidebar.render(data, tall))
    at = fn s -> Enum.find_index(lines, &(&1 =~ s)) end

    assert Sidebar.pick(data, tall, at.(Icons.home())) == {:switch_space, :orbis}
    assert Sidebar.pick(data, tall, at.("1")) == {:switch_space, 1}
    assert Sidebar.pick(data, tall, at.("2")) == {:switch_space, 2}
    # The `+` tile opens the new-workspace flow; the cog opens the config surface.
    assert Sidebar.pick(data, tall, at.(Icons.add())) == {:new_workspace}
    assert Sidebar.pick(data, tall, at.(Icons.settings())) == {:settings}
    # Tickets/Notes open their full-screen board.
    assert Sidebar.pick(data, tall, at.(Icons.ticket())) == {:open_board, :tickets}
    assert Sidebar.pick(data, tall, at.(Icons.note())) == {:open_board, :notes}
  end

  test "images/2 declares a kitty placement per tile: a digit icon per workspace + one per tool" do
    data = %{groups: groups(), active_key: :orbis}
    imgs = Sidebar.images(data, %{x: 0, y: 0, w: 12, h: 200})

    # 2 workspace DIGIT icons + Home + Tickets + Notes + settings + `+` = 7.
    assert length(imgs) == 7
    ids = Enum.map(imgs, & &1.id)
    assert Enum.uniq(ids) == ids
    assert Enum.all?(imgs, &(is_binary(&1.data) and is_map(&1.rect)))
    # workspace 1 uses the d1 digit icon; Home uses the home icon.
    assert Icons.image(:d1, %{x: 0, y: 0, w: 2, h: 1}).id in ids
    assert Icons.image(:home, %{x: 0, y: 0, w: 2, h: 1}).id in ids
  end

  test "a workspace's custom knobs icon shows instead of its digit; workspace_at targets the tile" do
    groups = [%{workspace: %{id: 7, name: "a", icon: "rocket"}, threads: [], crew: []}]
    data = %{groups: groups, active_key: :orbis}
    tall = %{@rect | h: 200}

    # The custom icon (rocket) is placed, not the position digit (d1).
    ids = data |> Sidebar.images(tall) |> Enum.map(& &1.id)
    assert Icons.image(:rocket, %{x: 0, y: 0, w: 1, h: 1}).id in ids
    refute Icons.image(:d1, %{x: 0, y: 0, w: 1, h: 1}).id in ids

    # Right-click hit-testing: the workspace tile resolves to its workspace; a tool tile does not.
    lines = texts(Sidebar.render(data, tall))
    ws_y = Enum.find_index(lines, &(&1 =~ "1"))
    home_y = Enum.find_index(lines, &(&1 =~ Icons.home()))
    assert %{id: 7} = Sidebar.workspace_at(data, tall, ws_y)
    assert Sidebar.workspace_at(data, tall, home_y) == nil
  end

  test "no workspaces (funes down) still renders the specials + actions" do
    rows = Sidebar.render(%{groups: [], active_key: :orbis}, @rect)
    lines = texts(rows)

    assert Enum.any?(lines, &(&1 =~ Icons.home()))
    assert Enum.any?(lines, &(&1 =~ Icons.add()))
  end
end
