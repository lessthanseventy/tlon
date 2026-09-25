defmodule Server.RepoPoolTest do
  # The release's pool serves Oban's concurrent jobs AND the always-on callers beside them (the
  # switchboard, the attention poller, the web UI, every coworker's MCP calls). A pool no bigger
  # than Oban's concurrency lets a busy queue starve a coworker's tool call.
  use ExUnit.Case, async: true

  @headroom 5

  test "the prod pool exceeds Oban's total queue concurrency by the always-on headroom" do
    config = Config.Reader.read!("config/config.exs", env: :prod, target: :host)
    pool = config[:server][Server.Repo][:pool_size]
    oban = config[:server][Oban][:queues] |> Keyword.values() |> Enum.sum()

    assert pool >= oban + @headroom, "pool_size #{pool} vs Oban concurrency #{oban} + #{@headroom}"
  end
end
