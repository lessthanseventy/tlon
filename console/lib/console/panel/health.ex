defmodule Console.Panel.Health do
  @moduledoc """
  HEALTH — the machine's always-on status: services up, system metrics, and installed tools.
  Best-effort and honest: a probe that fails yields "?", never a crash. Re-rendered on every
  Cockpit tick (not Bus-driven — system state changes on a clock, not a topic).

  Data is `%{version, funes_up, tlon_up, nix_gen, nix_behind, disk_pct, mem_pct, load_avg, tools}`.
  The `version` line (top) is the running build's identity — the answer to "is my change live?"
  """
  @behaviour Console.Panel

  import Console.Panel, only: [line: 2, blank: 0]

  @impl Console.Panel
  def topics(_assigns), do: []

  @impl Console.Panel
  # No probe yet (a fresh cockpit, or a failed read) — say so, don't crash the pane.
  def render(nil, rect), do: Console.Panel.clip([line("health probe hasn't run yet", :dim)], rect)

  def render(data, rect), do: Console.Panel.clip(rows(data), rect)

  defp rows(data) do
    version_rows(data[:version]) ++
      service_rows(data) ++
      [blank()] ++
      sys_rows(data) ++
      [blank()] ++
      tool_rows(data.tools)
  end

  # The build stamp: what code is actually running (git describe). Top of the panel so "is my fix
  # live?" is answerable at a glance. Absent (nil) → no line, never a crash.
  defp version_rows(nil), do: []
  defp version_rows(version), do: [[{"console ", :label}, {version, :normal}], blank()]

  # -- Services (up/down dots) --

  defp service_rows(data) do
    [
      row("server :4040", data.funes_up),
      row("tlon tmux", data.tlon_up)
    ]
  end

  defp row(label, true), do: [{"● ", :warm}, {label, :normal}]
  defp row(label, false), do: [{"○ ", :dim}, {label, :dim}]
  defp row(label, nil), do: [{"○ ", :dim}, {label <> " ?", :dim}]

  # -- System metrics --

  defp sys_rows(data) do
    [line("SYS", :label)] ++
      [nix_row(data.nix_gen, data.nix_behind)] ++
      [disk_row(data.disk_pct)] ++
      [mem_row(data.mem_pct)] ++
      [load_row(data.load_avg)]
  end

  defp nix_row(nil, _), do: [{"○ nix ", :dim}, {"?", :dim}]
  defp nix_row(gen, 0), do: [{"● nix ", :warm}, {"gen #{gen}", :normal}]
  defp nix_row(gen, behind) when behind > 0, do: [{"▲ nix ", :label}, {"gen #{gen} (#{behind} behind)", :normal}]
  defp nix_row(gen, _), do: [{"● nix ", :warm}, {"gen #{gen}", :normal}]

  defp disk_row(nil), do: [{"  disk ?", :dim}]
  defp disk_row(pct) when pct >= 90, do: [{"▲ disk ", :label}, {"#{pct}%", :normal}]
  defp disk_row(pct), do: [{"  disk ", :dim}, {"#{pct}%", :dim}]

  defp mem_row(nil), do: [{"  mem ?", :dim}]
  defp mem_row(pct) when pct >= 90, do: [{"▲ mem ", :label}, {"#{pct}%", :normal}]
  defp mem_row(pct), do: [{"  mem ", :dim}, {"#{pct}%", :dim}]

  defp load_row(nil), do: [{"  load ?", :dim}]
  defp load_row(avg) when avg >= 4.0, do: [{"▲ load ", :label}, {"#{avg}", :normal}]
  defp load_row(avg), do: [{"  load ", :dim}, {"#{avg}", :dim}]

  # -- Tools (padded name/version) --

  defp tool_rows(nil), do: [line("  tools ?", :dim)]
  defp tool_rows([]), do: [line("  tools ?", :dim)]

  defp tool_rows(tools) do
    [line("TOOLS", :label)] ++
      Enum.map(tools, &tool_row/1)
  end

  defp tool_row(%{name: name, version: version}) do
    [{"  ", :dim}, {String.pad_trailing(name, 8), :dim}, {version, :normal}]
  end
end
