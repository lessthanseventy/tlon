defmodule Server.MCP.WorkspaceToolsTest do
  # The workspace tools (register_workspace/list_workspaces/edit_workspace/remove_workspace)
  # are machine-GLOBAL: unlike every thread-scoped tool they read no identity from the
  # frame, so they are driven here by calling `execute/2` directly with a bare frame —
  # the honest unit of a tool that operates on the global `workspace` table via
  # `Server.Workspaces`. Every assertion reads back through the context (never Repo), the same one-source law
  # the tools obey.
  use ExUnit.Case, async: false

  alias Anubis.Server.Frame
  alias Server.MCP.Tool
  alias Server.Workspaces

  @frame %Frame{}

  setup do
    Server.TestDB.clean!()
    :ok
  end

  describe "register_workspace" do
    test "inserts a world and returns its id + name" do
      {:reply, resp, _} =
        Tool.RegisterWorkspace.execute(
          %{
            name: "Tlön",
            type: "code",
            scope: "machine",
            repos: ["modules/*"],
            roster: [%{"archetype" => "surveyor", "name" => "tertius"}],
            knobs: %{"lazygit" => true}
          },
          @frame
        )

      refute resp.isError
      payload = json(resp)
      assert payload["name"] == "Tlön"
      assert is_integer(payload["workspace_id"])

      world = Workspaces.by_name("Tlön")
      assert world.id == payload["workspace_id"]
      assert world.type == "code"
      assert world.scope == "machine"
      assert Enum.map(Workspaces.repos(world.id), & &1.path) == ["modules/*"]
    end

    test "a missing name is a graceful error, not a crash" do
      {:reply, resp, _} = Tool.RegisterWorkspace.execute(%{type: "code"}, @frame)
      assert resp.isError
      assert error_text(resp) =~ "name"
    end

    test "a duplicate name is a graceful changeset error" do
      {:ok, _} = Workspaces.register(%{name: "Tlön"})
      {:reply, resp, _} = Tool.RegisterWorkspace.execute(%{name: "Tlön"}, @frame)
      assert resp.isError
      assert is_binary(error_text(resp))
    end
  end

  describe "list_workspaces" do
    test "returns the shaped worlds, newest first" do
      {:ok, _} = Workspaces.register(%{name: "Tlön", repos: ["modules/*"]})
      {:ok, _} = Workspaces.register(%{name: "Uqbar", type: "blank"})

      {:reply, resp, _} = Tool.ListWorkspaces.execute(%{}, @frame)
      refute resp.isError
      worlds = json(resp)

      assert Enum.map(worlds, & &1["name"]) == ["Uqbar", "Tlön"]
      tlon = Enum.find(worlds, &(&1["name"] == "Tlön"))
      assert tlon["repos"] == [%{"path" => "modules/*", "remote" => nil, "default_branch" => nil}]
      assert tlon["type"] == "code"
      assert tlon["scope"] == "machine"
      assert is_binary(tlon["at"])
    end

    test "no worlds yields an empty list" do
      {:reply, resp, _} = Tool.ListWorkspaces.execute(%{}, @frame)
      refute resp.isError
      assert json(resp) == []
    end
  end

  describe "edit_workspace" do
    test "mutates a world's fields, identified by name" do
      {:ok, _} = Workspaces.register(%{name: "Tlön", type: "code"})

      {:reply, resp, _} =
        Tool.EditWorkspace.execute(
          %{name: "Tlön", type: "life", repos: ["docs/*"], knobs: %{"pulse" => false}},
          @frame
        )

      refute resp.isError
      shaped = json(resp)
      assert shaped["type"] == "life"
      assert shaped["repos"] == [%{"path" => "docs/*", "remote" => nil, "default_branch" => nil}]

      world = Workspaces.by_name("Tlön")
      assert world.type == "life"
      assert Enum.map(Workspaces.repos(world.id), & &1.path) == ["docs/*"]
      assert world.knobs == %{"pulse" => false}
    end

    test "a missing world is an error" do
      {:reply, resp, _} = Tool.EditWorkspace.execute(%{name: "nope", type: "life"}, @frame)
      assert resp.isError
      assert error_text(resp) =~ "nope"
    end
  end

  describe "remove_workspace" do
    test "deletes a world by name" do
      {:ok, _} = Workspaces.register(%{name: "keep"})
      {:ok, _} = Workspaces.register(%{name: "Tlön"})

      {:reply, resp, _} = Tool.RemoveWorkspace.execute(%{name: "Tlön"}, @frame)
      refute resp.isError
      assert json(resp)["removed"] == "Tlön"
      assert Workspaces.by_name("Tlön") == nil
    end

    test "the last world is refused, as a tool error" do
      {:ok, _} = Workspaces.register(%{name: "only"})

      {:reply, resp, _} = Tool.RemoveWorkspace.execute(%{name: "only"}, @frame)
      assert resp.isError
      assert error_text(resp) =~ "last workspace"
      assert Workspaces.by_name("only")
    end

    test "a missing world is an error" do
      {:reply, resp, _} = Tool.RemoveWorkspace.execute(%{name: "ghost"}, @frame)
      assert resp.isError
      assert error_text(resp) =~ "ghost"
    end
  end

  defp json(%{content: content, isError: false}) do
    %{"text" => text} = Enum.find(content, &(&1["type"] == "text"))
    JSON.decode!(text)
  end

  defp error_text(%{content: content, isError: true}) do
    %{"text" => text} = Enum.find(content, &(&1["type"] == "text"))
    text
  end
end
