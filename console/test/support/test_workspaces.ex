defmodule Console.TestWorkspaces do
  @moduledoc """
  The workspace-list fixture for suites that render/drive a Workspace space. The hardcoded
  fallback Workspace is gone (reshape slice A: funes self-seeds, aleph renders funes-down
  honestly), so a test that needs a Workspace pushes one through `Console.Workspaces.all/0`'s
  cache-down seam — process-scoped (`Process.put`), so async suites never race.

  `put/0` installs the classic one-workspace fixture (id 0 — what the old fallback keyed,
  so existing `active_key: 0` / `aleph-workspace-0` expectations hold); `put/1` any list.
  """

  @workspace %{
    id: 0,
    name: "Tlön",
    type: "code",
    scope: "machine",
    repos: ["modules/*"],
    bench: [
      %Server.Coworker{archetype: "surveyor", name: "tertius"},
      %Server.Coworker{archetype: "builder", name: "hronir"}
    ]
  }

  @doc "The one-workspace fixture row itself (for asserting against)."
  def workspace, do: @workspace

  @doc "Install the fixture workspace list for the calling process."
  def put(workspaces \\ [@workspace]) do
    Process.put(:aleph_workspaces, workspaces)
    :ok
  end
end
