defmodule Console.Panel.Author do
  @moduledoc """
  ORBIS' AUTHOR face: the editable server-workspace list — create (`n`) and delete (`d`) from the LIST
  view (D2, Chunk 1); `e` on the cursor workspace opens the in-place FIELD EDITOR (D2.4 Chunk 2a),
  `data[:edit]` present. List: one row per `Console.Workspaces.all/0` workspace (name · type · repo/bench
  counts), the `author_cursor` row washed `:selected` — same wash idiom as
  the old Overview. Data is `%{workspaces: [%{id, name, type, repos, bench, scope}],
  cursor, edit}` (`cursor`/`edit` View-injected). Hosted by the drawer as CONFIG
  (`Console.Cockpit.Drawer`, UX slice 1 task 5).

  The editor is a vertical 4-row field list (0 type · 1 scope · 2 repos · 3 bench), the `field`
  cursor washed `:selected`; fields 0/1 show the ring value inline (h/l cycles it, applied
  immediately — no draft/commit). `name` has no field — it's immutable
  (`Server.Workspace.edit_changeset` drops it), called out in the header instead. `Enter` on field 2/3
  (`edit.mode == :sub`) swaps in that field's sub-list — one row per repo (`path · remote ·
  default_branch`, UX slice 5) or bench seat (`archetype · name`), the `sub` cursor washed
  `:selected` — instead of the field list.

  The bench sub-list (D2.4 Chunk 2b, absorbs the Settings modal) ALSO renders each seat's
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
      {%{mode: :sub, field: 2} = edit, %{} = workspace} -> render_repos_sub(workspace, edit, rect)
      {%{mode: :sub, field: 3} = edit, %{} = workspace} -> render_bench_sub(workspace, edit, rect)
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
  # sub-list, `render_repos_sub`/`render_bench_sub`, when `edit.mode == :sub`).
  defp render_editor(workspace, edit, rect) do
    header = [
      line("ORBIS · author · edit", :header),
      [{Map.get(workspace, :name) || "?", :header}, {"  (name is immutable)", :dim}],
      blank()
    ]

    body = [
      field_row("type", Map.get(workspace, :type) || "?", edit.field == 0),
      field_row("scope", Map.get(workspace, :scope) || "?", edit.field == 1),
      field_row("repos", "#{length(Map.get(workspace, :repos) || [])} repos", edit.field == 2),
      field_row("bench", "#{length(Map.get(workspace, :bench) || [])} coworkers", edit.field == 3)
    ]

    footer = [blank(), line(@edit_hints, :dim)]

    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  defp field_row(label, value, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    [gutter, {String.pad_trailing(label, 8), :dim}, {value, style}]
  end

  # Field 2's sub-list (D2.4 Chunk 2b; ROWS since UX slice 5): one row per repo — `path`, then the
  # `remote` and `default_branch` a bare glob had nowhere to record. An unanswered column reads `—`
  # so "not set" is visibly a value and not a rendering gap. `sub` cursor washed :selected.
  defp render_repos_sub(workspace, edit, rect) do
    header = [line("ORBIS · author · edit · repos", :header), blank()]
    repos = Map.get(workspace, :repos) || []

    body =
      case repos do
        [] -> [line("no repos yet — a to add one (path [remote [branch]])", :dim)]
        rs -> rs |> Enum.with_index() |> Enum.map(fn {r, i} -> repo_row(r, i == edit.sub) end)
      end

    footer = [blank(), line(@sub_hints, :dim)]
    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  defp repo_row(repo, selected?) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}

    [
      gutter,
      {Map.get(repo, :path) || "?", style},
      {"  ", :normal},
      {Map.get(repo, :remote) || "—", :dim},
      {" · ", :dim},
      {Map.get(repo, :default_branch) || "—", :dim}
    ]
  end

  # Field 3's sub-list (D2.4 Chunk 2b/2c; %Server.Coworker{} seats since UX slice 5): one row per
  # bench seat (`archetype · name`, ★ on the lead) plus its effective model/yolo (Chunk 2b), the
  # `sub` cursor washed :selected. The lead is READ off the seat, not re-derived here.
  defp render_bench_sub(workspace, edit, rect) do
    header = [line("ORBIS · author · edit · bench", :header), blank()]
    bench = Map.get(workspace, :bench) || []
    knob = Map.get(edit, :knob, :model)

    body =
      case bench do
        [] -> [line("nobody on the bench yet — a to seat someone", :dim)]
        seats -> seats |> Enum.with_index() |> Enum.map(fn {c, i} -> bench_row(c, i == edit.sub, knob) end)
      end

    footer = [blank(), line(@roster_hints, :dim)]
    Console.Panel.clip(header ++ body ++ footer, rect)
  end

  # One bench row: archetype · name, then the model/yolo knobs (D2.4 Chunk 2b, absorbs Settings).
  # On the sub-selected row the ARMED knob (`Tab`) washes :accent — what Enter/Space will change.
  defp bench_row(%Server.Coworker{} = seat, selected?, knob) do
    style = if selected?, do: :selected, else: :normal
    gutter = if selected?, do: {"▸ ", :accent}, else: {"  ", :normal}
    norm = Profiles.roster_entry(seat)
    lead = if seat.lead?, do: " ★", else: ""

    [
      gutter,
      {"#{seat.archetype} · #{seat.name}#{lead}", style},
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
    repos = Map.get(w, :repos) || []
    bench = Map.get(w, :bench) || []

    [
      gutter,
      {Map.get(w, :name) || "?", style},
      {"  ", :normal},
      {Map.get(w, :type) || "?", :dim},
      {"  ", :normal},
      {"#{length(repos)} repos", :dim},
      {" · ", :dim},
      {"#{length(bench)} coworkers", :dim}
    ]
  end
end
