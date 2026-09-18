defmodule Server.Jobs.DrainTest do
  # One-brain piece E, slice 1: the switchboard's drain as a cron job. Oban is in manual testing
  # mode here — the job is performed by hand, and the cron entry is asserted from config.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  alias Server.Jobs.Drain

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "perform/1 drains the switchboard and returns :ok" do
    assert :ok = perform_job(Drain, %{})
  end

  test "the drain is on the minute cron" do
    plugins = Application.fetch_env!(:server, Oban)[:plugins]
    {_, cron} = Enum.find(plugins, &match?({Oban.Plugins.Cron, _}, &1))
    assert {"* * * * *", Drain} in cron[:crontab]
  end
end
