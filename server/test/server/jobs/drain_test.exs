defmodule Server.Jobs.DrainTest do
  # One-brain piece E, slice 1: the switchboard's drain as a cron job. Oban is in manual testing
  # mode here — the job is performed by hand, and the cron entry is asserted from config.
  use ExUnit.Case, async: false
  use Oban.Testing, repo: Server.Repo

  import Ecto.Query

  alias Server.Jobs.Drain

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "perform/1 drains the switchboard and returns :ok" do
    assert :ok = perform_job(Drain, %{})
  end

  test "perform/1 pages uqbar's study for a need newly in its group" do
    Server.Outside.ensure_citizens()
    {:ok, ws} = Server.Workspaces.register(%{name: "DrainWS"})
    path = Path.join(System.tmp_dir!(), "drain-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    :ok = Server.OperatorConfig.put("uqbar_routing", true, path)
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      File.rm(path)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    {:ok, q} = Server.Channel.open_thread(%{title: "q", workspace_id: ws.id})
    {:ok, _} = Server.Attention.ask(q.id, "daneri", "A or B?")

    assert :ok = perform_job(Drain, %{})

    {:ok, study} = Server.Outside.study(ws.id)

    assert [%{payload: %{"need_page" => [_]}}] =
             Server.Repo.all(
               from m in Server.Message,
                 where: m.thread_id == ^study.id and fragment("? \\? 'need_page'", m.payload)
             )
  end

  test "the drain is on the minute cron" do
    plugins = Application.fetch_env!(:server, Oban)[:plugins]
    {_, cron} = Enum.find(plugins, &match?({Oban.Plugins.Cron, _}, &1))
    assert {"* * * * *", Drain} in cron[:crontab]
  end
end
