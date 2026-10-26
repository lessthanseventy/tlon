defmodule Server.Office.NeedsPageTest do
  # Uqbar is paged on its study once per need that newly enters its group, debounced.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Server.Channel
  alias Server.Office.NeedsPage
  alias Server.Presence.Thinking

  setup do
    Server.TestDB.clean!()
    for n <- Server.Rollout.pending(), do: Server.Rollout.dismiss(n.id)
    Server.Outside.ensure_citizens()
    {:ok, ws} = Server.Workspaces.register(%{name: "PageWS"})
    path = Path.join(System.tmp_dir!(), "needs-page-#{System.pid()}-#{System.unique_integer([:positive])}.json")
    :ok = Server.OperatorConfig.put("uqbar_routing", true, path)
    prior = Application.get_env(:server, :operator_config_path)
    Application.put_env(:server, :operator_config_path, path)

    on_exit(fn ->
      File.rm(path)

      if prior,
        do: Application.put_env(:server, :operator_config_path, prior),
        else: Application.delete_env(:server, :operator_config_path)
    end)

    %{ws: ws, path: path}
  end

  defp question(ws) do
    {:ok, q} = Channel.open_thread(%{title: "q", workspace_id: ws.id})
    {:ok, _} = Server.Attention.ask(q.id, "daneri", "A or B?")
    "question:#{q.id}"
  end

  defp study(ws) do
    {:ok, study} = Server.Outside.study(ws.id)
    study
  end

  defp pages(ws) do
    Server.Repo.all(
      from m in Server.Message,
        where: m.thread_id == ^study(ws).id and m.author == "tlon" and fragment("? \\? 'need_page'", m.payload),
        order_by: m.id
    )
  end

  defp later(s), do: DateTime.add(DateTime.utc_now(), s, :second)

  test "a new need posts one page on the study naming its key and mentioning uqbar", %{ws: ws} do
    key = question(ws)
    NeedsPage.run()
    assert [%{payload: %{"need_page" => [^key]}, body: body}] = pages(ws)
    assert body =~ "@uqbar"
  end

  test "a key already paged is not paged again", %{ws: ws} do
    question(ws)
    NeedsPage.run()
    NeedsPage.run(later(600))
    assert [_] = pages(ws)
  end

  test "two new needs in one pass are one page naming both", %{ws: ws} do
    keys = [question(ws), question(ws)]
    NeedsPage.run()
    assert [%{payload: %{"need_page" => paged}}] = pages(ws)
    assert Enum.sort(paged) == Enum.sort(keys)
  end

  test "no page while uqbar is mid-turn; one once it is idle and the gap has passed", %{ws: ws} do
    question(ws)
    study = study(ws)
    Thinking.thinking(study.id, "uqbar")
    NeedsPage.run(later(600))
    assert pages(ws) == []
    Thinking.idle(study.id, "uqbar")
    NeedsPage.run(later(600))
    assert [_] = pages(ws)
  end

  test "a need within the gap of the last page waits; after it, a page for that one only", %{ws: ws} do
    first = question(ws)
    NeedsPage.run()
    second = question(ws)
    NeedsPage.run(later(60))
    assert [_] = pages(ws)
    NeedsPage.run(later(301))
    assert [%{payload: %{"need_page" => [^first]}}, %{payload: %{"need_page" => [^second]}}] = pages(ws)
  end

  test "a page older than the item does not count: the key pages again", %{ws: ws} do
    key = question(ws)
    NeedsPage.run()
    old = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

    Server.Repo.update_all(from(m in Server.Message, where: fragment("? \\? 'need_page'", m.payload)),
      set: [created_at: old]
    )

    NeedsPage.run(later(600))
    assert [_, %{payload: %{"need_page" => [^key]}}] = pages(ws)
  end

  test "with uqbar_routing off nothing is paged and no study is opened", %{ws: ws, path: path} do
    question(ws)
    :ok = Server.OperatorConfig.put("uqbar_routing", false, path)
    NeedsPage.run()
    assert Server.Repo.all(from t in Server.Thread, where: t.title == "uqbar's study") == []
  end
end
