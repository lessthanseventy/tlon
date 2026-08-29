defmodule Console.Panel.Crew do
  @moduledoc """
  The CREW pane — the Workspace's coworker pool at a glance: who exists (the workspace roster), what
  each one is (archetype · model · harness), whether it's on the clock right now (declared
  thinking > tmux-inferred working > idle > off), and where (its standing seat or the leaf it
  leads). `coworkers/6` is the pure assembly; `render/2` draws the pre-assembled
  `%{coworkers: [coworker()], leaves: {live, cap}}` — the same pane serves the cockpit sidebar
  and the general console's right rail.
  """
  @behaviour Console.Panel

  import Console.Panel, only: [blank: 0]

  alias Console.Presence
  alias Console.Profiles
  alias Server.Bus

  @type coworker :: %{
          name: String.t(),
          archetype: atom(),
          model: term(),
          harness: atom() | String.t(),
          status: :thinking | Presence.status(),
          seat: String.t() | nil,
          elapsed_s: non_neg_integer() | nil
        }

  @doc """
  Pure crew assembly — one row per recognized roster entry (unknown archetypes drop), the join
  of a Workspace roster with a tmux window snapshot, the leaf leads, and the explicit thinking
  declarations. `led_by` maps a funes handle (`<name>-machine`) to the thread ids it leads;
  `titles` thread id → title; `thinking` the `thread_id => %{agent => started_at}` declarations
  map (`%{}` where unavailable). Status precedence: declared thinking > tmux-inferred working >
  live > none. Pure (`now_s` is an argument) so it tests headless; each surface — the cockpit
  sidebar, the general console rail — assembles its own inputs.
  """
  @spec coworkers([map()], [Presence.window()], map(), map(), map(), integer()) :: [coworker()]
  def coworkers(roster, windows, led_by, titles, thinking, now_s) do
    for entry <- roster,
        %{archetype: arch, name: name} = Profiles.roster_entry(entry),
        arch != nil do
      profile = safe_instantiate(arch, name)
      {status, seat_tid, elapsed_s} = seat(windows, name, "#{name}-machine", led_by, thinking, now_s)

      %{
        name: name,
        archetype: arch,
        model: profile && profile.model,
        harness: (profile && profile.harness) || "?",
        status: status,
        seat: seat_tid && titles[seat_tid],
        elapsed_s: elapsed_s
      }
    end
  end

  # A declared thinking wins outright (the explicit signal never re-lists as merely inferred);
  # else the busiest of the standing window and any led leaf. `elapsed_s` (now - started_at) is
  # the trust signal (funes thread #3): a coworker "thinking" a long single turn must visibly
  # count up, not sit on a static word — only meaningful for the declared-thinking branch, since
  # tmux-inferred presence carries no start timestamp.
  defp seat(windows, name, handle, led_by, thinking, now_s) do
    case Enum.find(thinking, fn {_tid, agents} -> Map.has_key?(agents, handle) end) do
      {tid, agents} ->
        {:thinking, tid, max(now_s - agents[handle], 0)}

      nil ->
        {status, seat_tid} = Presence.coworker_seat(windows, name, Map.get(led_by, handle, []), now_s)
        {status, seat_tid, nil}
    end
  end

  defp safe_instantiate(arch, name) do
    Profiles.instantiate(%{archetype: arch, name: name})
  rescue
    _ -> nil
  end

  @impl Console.Panel
  def topics(_assigns), do: [Bus.sessions_topic()]

  @impl Console.Panel
  def render(%{coworkers: coworkers, leaves: {live, cap}}, rect) do
    header = [[{"leaves #{live}/#{cap}", :dim}], blank()]
    Console.Panel.clip(header ++ Enum.flat_map(coworkers, &entry(&1, rect.w)), rect)
  end

  # nil data (funes down / not a Workspace) renders nothing rather than crashing the paint.
  def render(_data, _rect), do: []

  defp entry(cw, w) do
    {glyph, label} = presence(cw.status)
    label = label <> elapsed_suffix(cw[:elapsed_s])

    [
      [{clip("#{cw.name}", w - 12), :normal}, {"  #{cw.archetype}", :dim}],
      [{"  #{glyph} ", glyph_style(cw.status)}, {clip(label <> seat(cw), w - 4), :dim}],
      [{clip("  #{short_model(cw.model)} · #{harness_label(cw.harness)}", w), :dim}],
      blank()
    ]
  end

  defp elapsed_suffix(nil), do: ""
  defp elapsed_suffix(seconds), do: " #{Console.Text.duration(seconds)}"

  defp presence(:thinking), do: {"⋯", "thinking"}
  defp presence(:working), do: {"●", "working"}
  defp presence(:live), do: {"●", "idle"}
  defp presence(:none), do: {"○", "off"}

  defp glyph_style(:thinking), do: :accent
  defp glyph_style(:working), do: :accent
  defp glyph_style(_status), do: :dim

  defp seat(%{status: :none}), do: ""
  defp seat(%{seat: nil}), do: ""
  defp seat(%{seat: title}), do: " · #{title}"

  defp harness_label(:claude_code), do: "claude"
  defp harness_label(other), do: to_string(other)

  defp short_model(nil), do: "base"
  defp short_model(%{model: m}), do: m
  defp short_model(m) when is_binary(m), do: m

  defp clip(_text, max) when max < 1, do: ""

  defp clip(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end
end
