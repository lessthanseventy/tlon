defmodule Server.Aleph do
  @moduledoc """
  The Aleph: a heavy hitter called in, never seated. An outside citizen (`Server.Outside`, its
  profile Fable in `Server.Profiles`), spawned on a thread when someone allowed to call it there
  @mentions it (`called?/2`): the operator, the workspace's manager or its tech lead. It reads the
  thread, does the one job asked, posts it, and the staffing pass dismisses it once it has answered
  and gone idle (`Server.Staffing`). One at a time: its window is named for it, not for a thread
  (`Server.Arbiter.Tmux`), so a second call waits for the first to finish.
  """
  alias Server.Thread

  @name "aleph"

  @doc "Its handle."
  def name, do: @name

  @doc """
  Whether `author`'s message on `thread` may call the Aleph in: the operator's, or the manager's or
  tech lead's of the thread's workspace. A coworker stuck on a thread asks one of them; the Aleph is
  not everyone's to wake.
  """
  def called?(%Thread{workspace_id: ws}, author) do
    seats = for s <- [Server.Workspaces.manager(ws), Server.Workspaces.lead(ws)], s, do: s.name
    String.downcase(author) in Enum.map([Server.OperatorConfig.operator() | seats], &String.downcase/1)
  end
end
