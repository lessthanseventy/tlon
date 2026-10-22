defmodule Server.MCP.SearchToolsTest do
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias Server.Channel
  alias Server.MCP.Tool

  setup do
    Server.TestDB.clean!()
    {:ok, thread} = Channel.open_thread(%{title: "search tools"})

    for body <- ~w(one two three four needle five six seven eight) do
      {:ok, _} = Channel.post(%{thread_id: thread.id, author: "a", body: body})
    end

    :ok
  end

  describe "search_history" do
    test "around gives each hit its conversation" do
      {:reply, resp, _} = Tool.SearchHistory.execute(%{query: "needle", around: 1}, %Frame{})
      assert [%{"window" => window}] = json(resp)["shown"]
      assert Enum.map(window, & &1["body"]) == ~w(four needle five)
    end

    test "around is capped at three turns either side" do
      {:reply, resp, _} = Tool.SearchHistory.execute(%{query: "needle", around: 50}, %Frame{})
      assert [%{"window" => window}] = json(resp)["shown"]
      assert Enum.map(window, & &1["body"]) == ~w(two three four needle five six seven)
    end

    test "a search that times out is a named tool error, not Internal error" do
      {:ok, thread} = Channel.open_thread(%{title: "busy"})

      Server.Repo.query!(
        """
        INSERT INTO message (thread_id, author, body, created_at)
        SELECT $1, 'a', 'ticket ' || g || ' review lonnrot verify filler words here', now()
        FROM generate_series(1, 20000) g
        """,
        [thread.id]
      )

      Application.put_env(:server, :search_timeout, 1)

      # its 20,000 rows, left for the next setup's row-by-row delete (a per-row FK trigger), took that
      # past its 15s timeout under a loaded gate; one TRUNCATE clears them at once
      on_exit(fn ->
        Application.delete_env(:server, :search_timeout)
        Server.Repo.query!("TRUNCATE message CASCADE")
      end)

      {:reply, resp, _} = Tool.SearchHistory.execute(%{query: "ticket review"}, %Frame{})
      assert %{isError: true, content: [%{"text" => text}]} = resp
      assert text =~ "ticket review"
      assert text =~ "timed out"
    end

    test "without around a hit is its snippet alone" do
      {:reply, resp, _} = Tool.SearchHistory.execute(%{query: "needle"}, %Frame{})
      assert [hit] = json(resp)["shown"]
      refute Map.has_key?(hit, "window")
    end
  end

  defp json(%{content: content, isError: false}) do
    %{"text" => text} = Enum.find(content, &(&1["type"] == "text"))
    JSON.decode!(text)
  end
end
