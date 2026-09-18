defmodule Console.Cockpit.Author do
  @moduledoc """
  The operator's authoring verbs over workspaces: the right-click context menu (icon picker,
  configure, the two-step delete) and CONFIG's writes (the drawer's Author pane) — register / remove / edit a
  workspace, a coworker's model or yolo knob. Every write goes to `Server.Workspaces` /
  `Console.Config` and answers the next cockpit state (a flash on failure, never a crash); the
  cockpit repaints it.
  """

  alias Console.Keymap
  alias Console.Panel
  alias Console.Safe
  alias Console.Server.Channels
  alias Console.Server.Tickets
  alias Console.Server.Workspaces
  alias Console.WorkspaceTemplates
  alias Server.Profiles

  @doc """
  An open overlay menu's keys: Esc closes, j/k/↑↓ move, Enter runs the cursor item's action —
  every other key is `:ignore`d so it can't leak to the frame underneath.
  """
  @spec handle_menu_key(map(), map()) :: map() | :ignore
  def handle_menu_key(%{key: :escape}, state), do: %{state | menu: nil}

  def handle_menu_key(%{key: :enter}, %{menu: %{items: items, cursor: c}} = state),
    do: menu_action(Enum.at(items, c).action, state)

  def handle_menu_key(key, state) do
    case Keymap.vertical(key) do
      nil -> :ignore
      delta -> move_menu(state, delta)
    end
  end

  defp move_menu(%{menu: %{items: items, cursor: c} = menu} = state, delta) do
    n = max(length(items), 1)
    %{state | menu: %{menu | cursor: rem(c + delta + n, n)}}
  end

  @doc "A workspace's right-click context menu, anchored at the click cell."
  def workspace_menu(ws, x, y) do
    %{
      title: ws.name,
      x: x,
      y: y,
      cursor: 0,
      items: [
        %{label: "Set icon…", action: {:icon_picker, ws}},
        %{label: "Configure", action: {:configure_ws, ws}},
        %{label: "Delete", action: {:delete_ws, ws}, danger: true}
      ]
    }
  end

  @doc """
  A rail thread's context menu (channels slice 1b): move it to any OTHER channel of its
  workspace. `channels` is the sidebar's list for the workspace; its own channel is left out.
  """
  def thread_menu(thread, channels, x, y) do
    moves =
      for channel <- channels, channel.id != thread[:channel_id] do
        %{label: "Move to ##{channel.name}", action: {:move_thread, thread, channel}}
      end

    %{title: thread.title, x: x, y: y, cursor: 0, items: moves ++ [%{label: "Cancel", action: :close}]}
  end

  @doc "A rail channel's context menu: a new channel in its workspace; delete (topic channels only)."
  def channel_menu(channel, x, y) do
    delete =
      if channel[:kind] == "topic",
        do: [%{label: "Delete ##{channel.name}", action: {:delete_channel, channel}, danger: true}],
        else: []

    %{title: "##{channel.name}", x: x, y: y, cursor: 0, items: [%{label: "New channel…", action: :new_channel} | delete]}
  end

  @doc """
  The TICKETS board's `b` menu (UX slice 4): pick which OTHER ticket blocks this one. Phrased as
  "Blocked by #N" because that is how the operator thinks about it; the row it writes is the
  inverse — `link(other, ticket, "blocks")` — since a link is stored one way and read both.
  Already-blocking tickets are offered as an unlink, so the same menu adds and removes.
  """
  def blocker_menu(ticket, others, blocking, x, y) do
    items =
      for other <- others, other.id != ticket.id do
        if other.id in blocking,
          do: %{label: "Unblock — ##{other.id} #{other.title}", action: {:unblock, ticket, other}},
          else: %{label: "Blocked by ##{other.id} #{other.title}", action: {:block, ticket, other}}
      end

    %{title: "##{ticket.id} #{ticket.title}", x: x, y: y, cursor: 0, items: items ++ [%{label: "Cancel", action: :close}]}
  end

  defp confirm_delete_channel_menu(channel, x, y) do
    %{
      title: "delete?",
      x: x,
      y: y,
      cursor: 1,
      items: [
        %{
          label: "Delete ##{channel.name} (threads → #general)",
          action: {:confirm_delete_channel, channel},
          danger: true
        },
        %{label: "Cancel", action: :close}
      ]
    }
  end

  # The Set-icon picker: the workspace-icon choices, plus a reset to the position number.
  defp icon_picker_menu(ws, x, y) do
    icons =
      Enum.map(Console.Icons.workspace_icons(), fn name ->
        %{label: to_string(name), action: {:set_icon, ws, to_string(name)}, icon: name}
      end)

    %{title: "icon", x: x, y: y, cursor: 0, items: [%{label: "number", action: {:set_icon, ws, nil}} | icons]}
  end

  defp confirm_delete_menu(ws, x, y) do
    %{
      title: "delete?",
      x: x,
      y: y,
      cursor: 1,
      items: [
        %{label: "Delete #{ws.name}", action: {:confirm_delete, ws}, danger: true},
        %{label: "Cancel", action: :close}
      ]
    }
  end

  @doc "A click on the open menu: a picked row runs its action; a miss closes the menu."
  def apply_menu({:menu_pick, action}, state), do: menu_action(action, state)
  def apply_menu(_none, state), do: %{state | menu: nil}

  defp menu_action(:close, state), do: %{state | menu: nil}

  # Configure → the drawer's CONFIG pane with the cursor on that workspace.
  defp menu_action({:configure_ws, ws}, state) do
    # the cache (what CONFIG lists), not a server round-trip
    cursor = Enum.find_index(Console.Workspaces.all(), &(&1.id == ws.id)) || 0
    Console.Cockpit.Drawer.open(%{state | menu: nil, author_cursor: cursor}, :config)
  end

  defp menu_action({:delete_ws, ws}, %{menu: %{x: x, y: y}} = state), do: %{state | menu: confirm_delete_menu(ws, x, y)}

  defp menu_action({:confirm_delete, ws}, state), do: %{remove_workspace!(state, ws.id) | menu: nil}

  defp menu_action({:icon_picker, ws}, %{menu: %{x: x, y: y}} = state), do: %{state | menu: icon_picker_menu(ws, x, y)}

  defp menu_action({:set_icon, ws, icon}, state), do: %{set_workspace_icon(state, ws.id, icon) | menu: nil}

  # Channels (slice 1b). A move is a thread event, so the rail re-reads on its own.
  defp menu_action({:move_thread, thread, channel}, state) do
    flash =
      case Safe.value(fn -> Channels.move(Console.Server.Channel.thread(thread.id), channel.id) end, nil) do
        {:ok, _} -> "moved “#{thread.title}” to ##{channel.name}"
        _ -> "couldn't move “#{thread.title}”"
      end

    %{state | menu: nil, flash: flash, open_channel: channel.id}
  end

  defp menu_action(:new_channel, state), do: %{state | menu: nil, input: %{kind: :new_channel, buffer: "", cursor: 0}}

  defp menu_action({:delete_channel, channel}, %{menu: %{x: x, y: y}} = state),
    do: %{state | menu: confirm_delete_channel_menu(channel, x, y)}

  defp menu_action({:confirm_delete_channel, channel}, state), do: %{delete_channel(state, channel) | menu: nil}

  # A block is written from the BLOCKER's end (`other blocks ticket`) — one row, read both ways.
  defp menu_action({:block, ticket, other}, state) do
    flash =
      case Safe.value(fn -> Tickets.link(other.id, ticket.id, "blocks") end, nil) do
        {:ok, _} -> "##{ticket.id} is blocked by ##{other.id}"
        _ -> "couldn't link ##{ticket.id}"
      end

    %{state | menu: nil, flash: flash}
  end

  defp menu_action({:unblock, ticket, other}, state) do
    _ = Safe.value(fn -> Tickets.unlink(other.id, ticket.id, "blocks") end, nil)
    %{state | menu: nil, flash: "##{ticket.id} no longer blocked by ##{other.id}"}
  end

  defp menu_action(_unknown, state), do: %{state | menu: nil}

  @doc "Delete a topic channel (its threads go home to #general); the open channel falls back to #general."
  def delete_channel(state, channel) do
    case Safe.value(fn -> Channels.delete(channel.id) end, nil) do
      {:ok, _} -> %{state | flash: "deleted ##{channel.name} — its threads are in #general", open_channel: nil}
      {:error, :general} -> %{state | flash: "#general can't be deleted"}
      _ -> %{state | flash: "couldn't delete ##{channel.name}"}
    end
  end

  @doc "Create a topic channel in the active workspace and open it."
  def create_channel(state, name) do
    name = name |> String.trim() |> String.trim_leading("#")

    case Safe.value(fn -> Channels.create(Console.Space.active_workspace_id(state), name) end, nil) do
      {:ok, channel} -> %{state | flash: "created ##{channel.name}", open_channel: channel.id}
      {:error, %{errors: errors}} -> %{state | flash: "couldn't create ##{name}: #{inspect(Keyword.keys(errors))}"}
      _ -> %{state | flash: "couldn't create ##{name}"}
    end
  end

  # Merge the chosen icon into the workspace's knobs (nil clears it → back to the number).
  defp set_workspace_icon(state, id, icon) do
    case Enum.find(Workspaces.all(), &(&1.id == id)) do
      %{knobs: knobs} -> edit_workspace!(state, id, %{knobs: put_or_delete_icon(knobs || %{}, icon)})
      _ -> state
    end
  end

  defp put_or_delete_icon(knobs, nil), do: Map.delete(knobs, "icon")
  defp put_or_delete_icon(knobs, icon), do: Map.put(knobs, "icon", icon)

  @doc "The overlay's placements (Border + the Menu content), clamped on screen — painted last, on top."
  def menu_placements(nil, _w, _h), do: []

  def menu_placements(%{items: items} = menu, w, h) do
    content_w = max(Panel.Menu.width(menu), String.length(menu[:title] || ""))
    box_w = min(content_w + 4, w)
    box_h = min(length(items) + 2, max(h - 2, 2))
    x = menu.x |> min(w - box_w) |> max(0)
    y = menu.y |> min(h - box_h - 2) |> max(0)
    rect = %{x: x, y: y, w: box_w, h: box_h}
    inset = %{x: x + 2, y: y + 1, w: max(box_w - 4, 1), h: max(box_h - 2, 1)}

    [
      {Panel.Border, %{focused: true, digit: nil, title: menu[:title], tabs: nil, hint: nil}, rect},
      {Panel.Menu, menu, inset}
    ]
  end

  @doc false
  # Register a workspace from `template` + the operator-typed `name` (D2.3's `n` verb). `{:ok, _}`
  # clears the input and flashes; `{:error, changeset}` (a blank OR duplicate name — both are the
  # server changeset's job, not re-validated here) flashes the reason and REOPENS the input with
  # what was typed, so a rejected name can be edited and resubmitted rather than retyped from
  # scratch. Wrapped like `create_thread`/`post_message` — a server hiccup flashes, never crashes
  # the cockpit.
  def register_workspace!(state, template, name) do
    Safe.flash_on_error(state, "create", fn ->
      case Workspaces.register(WorkspaceTemplates.new_workspace_attrs(template, name)) do
        {:ok, workspace} ->
          %{state | input: nil, flash: "created #{workspace.name}"}

        {:error, changeset} ->
          %{
            state
            | input: %{kind: :new_workspace, buffer: name, cursor: String.length(name), template: template},
              flash: "couldn't create “#{name}” — #{changeset_error(changeset)}"
          }
      end
    end)
  end

  @doc false
  # Remove workspace `id` (D2.5's second `d`). Guards against stranding the cockpit on a deleted
  # active workspace (falls back to the first remaining workspace) and clamps `author_cursor` to the shrunk list. A missing
  # workspace (already gone) or a server hiccup flashes, never crashes.
  def remove_workspace!(state, id) do
    Safe.flash_on_error(state, "delete", fn ->
      case Workspaces.get(id) do
        nil ->
          %{state | flash: "workspace ##{id} already gone"}

        workspace ->
          case Workspaces.remove(workspace) do
            {:ok, _} ->
              state
              |> Map.put(:active_key, if(state.active_key == id, do: first_remaining(id), else: state.active_key))
              |> Map.put(:author_cursor, clamp_author_cursor(state.author_cursor))
              |> Map.put(:flash, "deleted #{workspace.name}")

            {:error, :last_workspace} ->
              %{state | flash: "couldn't delete #{workspace.name} — the last workspace; threads must have a home"}

            {:error, changeset} ->
              %{state | flash: "couldn't delete #{workspace.name} — #{changeset_error(changeset)}"}
          end
      end
    end)
  end

  # Re-clamp the author cursor against the POST-delete count (one fewer row) — same edge-clamp
  # discipline as the keymap's move_author_cursor, applied here since a delete can shrink the list
  # out from under a cursor sitting on (or past) the new last row.
  defp clamp_author_cursor(cursor), do: max(min(cursor, max(length(Workspaces.all()) - 1, 0)), 0)

  @doc false
  # Apply one field edit (D2.4 Chunk 2a: the editor's type/scope rings, and the paths/roster
  # sub-list's add/remove) immediately — no draft/commit step, mirroring how Settings applies each
  # change on the spot. `name` is immutable (`Workspace.edit_changeset` drops it — see server/workspace.ex);
  # nothing here special-cases it. Same missing/error/rescue shape as `register_workspace!`/
  # `remove_workspace!`. On success, re-clamps `author_edit.sub` against the POST-edit paths/roster
  # length (a removal can strand `sub` past the shrunk list, same reasoning as
  # `clamp_author_cursor/1` above).
  # The active workspace was just deleted: land on the first one the server still has (its own
  # read, not the Bus-fed cache, which may not have caught up); `0` is the no-workspace sentinel.
  defp first_remaining(id) do
    case Enum.find(Workspaces.all(), &(&1.id != id)) do
      %{id: next} -> next
      nil -> 0
    end
  end

  def edit_workspace!(state, id, attrs) do
    Safe.flash_on_error(state, "edit", fn ->
      case Workspaces.get(id) do
        nil ->
          %{state | flash: "workspace ##{id} already gone"}

        workspace ->
          case Workspaces.edit(workspace, attrs) do
            {:ok, updated} -> reclamp_author_edit_sub(%{state | flash: "updated #{updated.name}"})
            {:error, changeset} -> %{state | flash: "couldn't update #{workspace.name} — #{changeset_error(changeset)}"}
          end
      end
    end)
  end

  # Only reachable when `author_edit` is actually mid-edit on a paths/roster sub-list (field 2/3) —
  # elsewhere (the type/scope rings, or no editor open) this is a no-op via the fallback clause.
  defp reclamp_author_edit_sub(%{author_edit: %{id: id, field: field} = edit} = state) when field in [2, 3] do
    # The live ROWS, not a workspace struct: since UX slice 5 the scope and the bench are their own
    # tables, and `Map.get(%Server.Workspace{}, :repos)` quietly answers nil (a struct is a map with
    # fixed keys, and `Map.get` does not raise) — which then raised inside `length/1` and was
    # swallowed by `Safe`, leaving the cursor un-clamped with nothing said.
    len = length(sub_list_rows(field, id))
    %{state | author_edit: %{edit | sub: edit.sub |> min(max(len - 1, 0)) |> max(0)}}
  end

  defp reclamp_author_edit_sub(state), do: state
  defp sub_list_rows(2, workspace_id), do: Workspaces.repos(workspace_id)
  defp sub_list_rows(3, workspace_id), do: Workspaces.bench(workspace_id)

  # The bench sub-editor knob (D2.4 Chunk 2b, absorbs Settings): cycle the sub-selected coworker's
  # model ring, or flip its ask-vs-allow default. Both write a `workspace_policy` row for THIS
  # workspace × agent and apply on the coworker's next spawn.
  #
  # The seat comes off the LIVE bench, not the effect's bare name: its archetype is the model ring's
  # fallback and its agent_id is what a policy is keyed by.
  @doc false
  # The roster sub-editor's Tab+Enter/Space knob (D2.4 Chunk 2b — absorbs the Settings modal):
  # cycle the sub-selected coworker's model ring, or flip its yolo policy, writing Console.Config
  # (file-backed, applies on the coworker's NEXT SPAWN — same honest scope as the `m` verb/old
  # Settings). Looks the roster entry up off the LIVE workspace (Workspaces.get, like edit_workspace!) rather
  # than trust the effect's bare name, so the entry's archetype (the model ring's default-fallback
  # source) is available.
  def apply_coworker_knob!(%{author_edit: %{id: workspace_id}} = state, name, knob) do
    Safe.flash_on_error(state, "settings write", fn ->
      case roster_entry_for(state, name) do
        nil -> %{state | flash: "#{name}: not on this bench"}
        seat -> %{state | flash: apply_knob(workspace_id, seat, knob)}
      end
    end)
  end

  # No editor open means no workspace to key a policy by — a knob without a pairing is a no-op.
  def apply_coworker_knob!(state, _name, _knob), do: state

  defp roster_entry_for(%{author_edit: %{id: id}}, name), do: id |> Workspaces.bench() |> Enum.find(&(&1.name == name))

  defp apply_knob(workspace_id, %Server.Coworker{} = seat, :model) do
    norm = Profiles.roster_entry(seat)
    next = Profiles.next_model(Profiles.instantiate(norm, workspace_id).model)
    {:ok, _} = Workspaces.set_policy(workspace_id, seat.agent_id, %{model: wire_model(next)})
    "#{seat.name} driver → #{next.provider}/#{next.model} — applies on next spawn (console:reset)"
  end

  defp apply_knob(workspace_id, %Server.Coworker{} = seat, :yolo) do
    next = if current_ask_default(workspace_id, seat) == "allow", do: "ask", else: "allow"
    {:ok, _} = Workspaces.set_policy(workspace_id, seat.agent_id, %{ask_default: next})
    label = if next == "allow", do: "yolo (auto-approve)", else: "ask"
    "#{seat.name} permissions → #{label} — applies on next spawn (console:reset)"
  end

  @doc """
  A short `field message; field message` sentence from an Ecto changeset — a duplicate name's
  UNIQUE violation reads "name has already been taken", not an inspect dump.
  """
  def changeset_error(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field} #{Enum.join(errors, ", ")}" end)
  end

  @doc "Advance a coworker's driver one step round the ring and persist it; returns the flash string."
  def cycle_model!(profile_name) do
    current = Profiles.fetch(profile_name)
    next = Profiles.next_model(current && current.model)
    Console.Config.put_coworker_model(profile_name, next)
    "coworker driver → #{next.provider}/#{next.model} — applies on next spawn (console:reset)"
  end

  @doc false
  # CONFIG's repos sub-list `a` (UX slice 5). The buffer is `path [remote [branch]]`: one prompt for
  # all three columns rather than a second and a third, and whitespace is not legal in any of them
  # anyway. A blank buffer adds nothing — Enter on an empty box already closes it upstream.
  def add_repo!(state, id, buffer) do
    Safe.flash_on_error(state, "add repo", fn ->
      case String.split(buffer || "", ~r/\s+/, trim: true) do
        [] ->
          state

        [path | rest] ->
          attrs = %{path: path, remote: Enum.at(rest, 0), default_branch: Enum.at(rest, 1)}

          case Workspaces.add_repo(id, attrs) do
            {:ok, repo} -> reclamp_author_edit_sub(%{state | flash: "added #{repo.path}"})
            {:error, changeset} -> %{state | flash: "couldn't add #{path} — #{changeset_error(changeset)}"}
          end
      end
    end)
  end

  @doc false
  # CONFIG's repos sub-list `x`/`d`. Addressed by ROW id, so a list that shifted under the cursor
  # cannot make this delete a different repo than the one the cursor was on.
  def remove_repo!(state, _id, repo_id) do
    Safe.flash_on_error(state, "remove repo", fn ->
      case Workspaces.get_repo(repo_id) do
        nil ->
          %{state | flash: "that repo is already gone"}

        repo ->
          {:ok, _} = Workspaces.remove_repo(repo)
          reclamp_author_edit_sub(%{state | flash: "removed #{repo.path}"})
      end
    end)
  end

  @doc false
  # CONFIG's bench sub-list `a` (UX slice 5): seat a coworker. Registers its agent if the handle is
  # new — the bench IS the agent table now, so there is no "on demand" left to defer it to.
  def seat!(state, id, attrs) do
    Safe.flash_on_error(state, "seat", fn ->
      case Workspaces.seat(id, attrs) do
        {:ok, coworker} -> reclamp_author_edit_sub(%{state | flash: "seated #{coworker.name}"})
        {:error, changeset} -> %{state | flash: "couldn't seat #{attrs[:name]} — #{changeset_error(changeset)}"}
      end
    end)
  end

  @doc false
  # CONFIG's bench sub-list `x`/`d`: unseat by ROW id. The AGENT survives — it is durable identity
  # that threads and sessions point at, and a bench edit is not a reason to destroy one.
  def unseat!(state, _id, seat_id) do
    Safe.flash_on_error(state, "unseat", fn ->
      case Workspaces.unseat(seat_id) do
        {:ok, _seat} -> reclamp_author_edit_sub(%{state | flash: "unseated"})
        {:error, :no_such_seat} -> %{state | flash: "that seat is already gone"}
      end
    end)
  end

  defp current_ask_default(workspace_id, %Server.Coworker{agent_id: agent_id}) do
    case Workspaces.policy(workspace_id, agent_id) do
      %Server.Policy{ask_default: value} -> value
      nil -> nil
    end
  end

  defp wire_model(%{provider: p, model: m} = next),
    do: %{"provider" => p, "model" => m, "thinking" => next[:thinking] || "medium"}
end
