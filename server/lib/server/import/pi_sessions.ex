defmodule Server.Import.PiSessions do
  @moduledoc """
  pi's transcripts as closed threads, the same way `Server.Import.ClaudeSessions` imports Claude
  Code's (that module parses both formats): the operator's own sessions under
  `~/.pi/agent/sessions`, and the ones he held with a coworker profile under
  `~/.pi/profiles/*/sessions`. Machine-driven sessions are skipped by their opener.
  """

  alias Server.Import.ClaudeSessions

  @doc "Import every pi transcript under `dir` (normally `~/.pi`) into `workspace_id`."
  def import_dir(dir, workspace_id) do
    root = Path.expand(dir)

    ["agent/sessions/*/*.jsonl", "profiles/*/sessions/*/*.jsonl"]
    |> Enum.map(&Path.join(root, &1))
    |> ClaudeSessions.import_glob(workspace_id)
  end
end
