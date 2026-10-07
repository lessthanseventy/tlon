defmodule Server.Jobs.GradeTest do
  use ExUnit.Case, async: false

  setup do
    Server.TestDB.clean!()
    :ok
  end

  test "a thread that has left review since is not graded" do
    {:ok, thread} = Server.Workline.open(%{title: "moved on", slug: "moved-on", stage: "build"})
    assert :ok = Server.Jobs.Grade.perform(%Oban.Job{args: %{"thread_id" => thread.id}})

    refute Server.Repo.get_by(Server.Event, correlation: "workline:moved-on:grade")
  end
end
