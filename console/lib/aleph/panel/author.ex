defmodule Console.Panel.Author do
  @moduledoc """
  ORBIS' AUTHOR face: the editable funes-workspace list — create (`n`) and delete (`d`) from the LIST
  view (D2, Chunk 1); `e` on the cursor workspace opens the in-place FIELD EDITOR (D2.4 Chunk 2a),
  `data[:edit]` present. List: one row per `Console.Workspaces.all/0` workspace (name · type · path/roster
  counts), the `author_cursor` row washed `:selected` — same wash idiom as
  `Console.Panel.Overview`/`Leaves`. Data is `%{workspaces: [%{id, name, type, paths, roster, scope}],
  cursor, edit}` (`cursor`/`edit` View-injected). Replaces Overview as Orbis' center only while
  `orbis_face == :author` (`Console.View.compose/3`).

  The editor is a vertical 4-row field list (0 type · 1 scope · 2 paths · 3 roster), the `field`
  cursor washed `:selected`; fields 0/1 show the ring value inline (h/l cycles it, applied
  immediately — no draft/commit). `name` has no field — it's immutable
  (`Server.Workspace.edit_changeset` drops it), called out in the header instead. `Enter` on field 2/3
  (`edit.mode == :sub`) swaps in that field's sub-list — one row per path/roster entry (roster:
  `archetype · name`), the `sub` cursor washed `:selected` — instead of the field list.

  The roster sub-list (D2.4 Chunk 2b, absorbs the Settings modal) ALSO renders each entry's
  effective model and yolo — the two knobs Settings used to own. Model resolves
  Config-or-archetype-default via `Profiles.instantiate/1` (the same precedence the `m` verb and
  Settings used); yolo reads `Console.Config.coworker_yolo/1` directly. On the sub-selected row, the
  knob `Tab` has armed (`edit.knob`) washes `:accent` — the cue for what `Enter`/`Space` will
  change.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  alias Console.Config
  alias Console.Profiles
  alias Server.Bus

  @hints "j/k row · n new · e edit · d delete · a survey"
  @edit_hints "j/k field · h/l cycle · Enter list · Esc back"
  @sub_hints "j/k row · a add · x/d remove · Esc back"
  @roster_hints "j/k row · a add · x/d remove · Tab knob · Enter apply · Esc back"

  @impl Console.Panel
  def topics(_assigns), do: [Bus.workspaces_topic()]

  @impl Console.Panel
  def render(%{workspaces: workspaces} = data, rect) do
    case {Map.get(data, :edit), Enum.find(workspaces, &(&1.id == data[:edit][:id]))} do
      {%{mode: :sub, field: 2} = edit, %{} = workspace} -> render_paths_sub(workspace, edit, rect)
      {%{mode: :sub, field: 3} = edit, %{} = workspace} -> render_roster_sub(workspace, edit, rect)
      {%{} = edit, %{} = workspace} -> render_editor(workspace, edit, rect)
      _ -> render_list(workspaces, Map.get(data, :cursor, 0), rect)
    end
  end

  defp render_list(workspaces, cursor, rect) do
    header = [line("ORBIS · author", :header), blank()]

    body =
      case workspaces do
        [] -> [line("no workspaces yet — n to create one", :dim)]
        ws -> ws |> Enum.with_index() |> Enum.map(fn {w, i} -> workspace_row(w, i == cursor) end)
      end

    footer = [blank(), line(@hints, :dim)]

    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  # The field list (fields 0/1's rings inline; 2/3 show counts — their own row swaps in a
  # sub-list, `render_paths_sub`/`render_roster_sub`, when `edit.mode == :sub`).
  defp render_editor(workspace, edit, rect) do
    header = [
      line("ORBIS · author · edit", :header),
      [{Map.get(workspace, :name) || "?", :header}, {"  (name is immutable)", :dim}],
      blank()
    ]

    body = [
      field_row("type", Map.get(workspace, :type) || "?", edit.field == 0),
      field_row("scope", Map.get(workspace, :scope) || "?", edit.field == 1),
      field_row("paths", "#{length(Map.get(workspace, :paths) || [])} paths", edit.field == 2),
      field_row("roster", "#{length(Map.get(workspace, :roster) || [])} roster", edit.field == 3)
    ]

    footer = [blank(), line(@edit_hints, :dim)]

    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  defp field_row(label, value, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    [gutter, {String.pad_trailing(label, 8), :dim}, {value, style}]
  end

  # Field 2's sub-list (D2.4 Chunk 2b): one row per path, the `sub` cursor washed :selected — same
  # gutter/wash idiom as the list/field views.
  defp render_paths_sub(workspace, edit, rect) do
    header = [line("ORBIS · author · edit · paths", :header), blank()]
    paths = Map.get(workspace, :paths) || []

    body =
      case paths do
        [] -> [line("no paths yet — a to add one", :dim)]
        ps -> ps |> Enum.with_index() |> Enum.map(fn {p, i} -> sub_row(p, i == edit.sub) end)
      end

    footer = [blank(), line(@sub_hints, :dim)]
    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  defp sub_row(text, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    [gutter, {text, style}]
  end

  # Field 3's sub-list (D2.4 Chunk 2b/2c): one row per roster entry (`archetype · name`, the funes
  # WIRE shape — string-keyed) plus its effective model/yolo (Chunk 2b), the `sub` cursor washed
  # :selected.
  defp render_roster_sub(workspace, edit, rect) do
    header = [line("ORBIS · author · edit · roster", :header), blank()]
    roster = Map.get(workspace, :roster) || []
    knob = Map.get(edit, :knob, :model)

    body =
      case roster do
        [] -> [line("no roster yet — a to add one", :dim)]
        rs -> rs |> Enum.with_index() |> Enum.map(fn {r, i} -> roster_row(r, i == edit.sub, knob) end)
      end

    footer = [blank(), line(@roster_hints, :dim)]
    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  defp roster_entry_text(%{"archetype" => archetype, "name" => name}), do: "#{archetype} · #{name}"
  defp roster_entry_text(entry), do: inspect(entry)

  # One roster row: archetype · name, then the model/yolo knobs (D2.4 Chunk 2b, absorbs Settings).
  # On the sub-selected row the ARMED knob (`Tab`) washes :accent — what Enter/Space will change.
  defp roster_row(entry, selected?, knob) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    norm = Profiles.roster_entry(entry)

    [
      gutter,
      {roster_entry_text(entry), style},
      {"  ", :normal},
      {format_model(effective_model(norm)), knob_style(selected?, knob, :model)},
      {"  ", :normal},
      {yolo_label(Config.coworker_yolo(norm.name)), knob_style(selected?, knob, :yolo)}
    ]
  end

  defp knob_style(true, k, k), do: :accent
  defp knob_style(_selected?, _armed, _field), do: :dim

  # Config-or-archetype-default, same precedence `instantiate/1` folds in for a real spawn. An
  # unresolvable archetype/name (bad wire data) degrades to nil rather than raising mid-render.
  defp effective_model(%{archetype: nil}), do: nil
  defp effective_model(%{name: nil}), do: nil
  defp effective_model(norm), do: Profiles.instantiate(norm).model

  defp format_model(%{provider: prov, model: model}), do: "#{prov}/#{model}"
  defp format_model(_), do: "?"

  defp yolo_label(true), do: "yolo"
  defp yolo_label(_), do: "ask"

  # No click target yet — the editor is keyboard-only (Chunk 2a/b/c). Kept as an explicit no-op
  # (not left unimplemented), same idiom as the list's pre-Chunk-2 pick/3.
  @impl Console.Panel
  def pick(_data, _rect, _local_y), do: nil

  defp workspace_row(w, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    paths = Map.get(w, :paths) || []
    roster = Map.get(w, :roster) || []

    [
      gutter,
      {Map.get(w, :name) || "?", style},
      {"  ", :normal},
      {Map.get(w, :type) || "?", :dim},
      {"  ", :normal},
      {"#{length(paths)} paths", :dim},
      {" · ", :dim},
      {"#{length(roster)} roster", :dim}
    ]
  end
end
