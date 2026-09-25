defmodule Console.Server do
  @moduledoc """
  The cockpit's view of the server: `Console.Server.*` mirrors `Server.*`, one module per
  context, every function routed through `Console.Backend`. Call sites alias these instead of
  the server's modules; see `Console.Server.Facade` for how the mirror is built.
  """
  use Console.Server.Facade, target: Server

  alias Console.Server.Facade

  defmodule Board, do: use(Facade, target: Server.Board)
  defmodule Channel, do: use(Facade, target: Server.Channel, local: [operator?: 1])
  defmodule Channels, do: use(Facade, target: Server.Channels)
  defmodule Dossier, do: use(Facade, target: Server.Dossier)
  defmodule Staff, do: use(Facade, target: Server.Staff)
  defmodule Notes, do: use(Facade, target: Server.Notes)
  defmodule Tickets, do: use(Facade, target: Server.Tickets)
  defmodule Workspaces, do: use(Facade, target: Server.Workspaces)
  defmodule Doctor, do: use(Facade, target: Server.Doctor)
  defmodule Presence.Thinking, do: use(Facade, target: Server.Presence.Thinking)
  defmodule MCP.Spawn, do: use(Facade, target: Server.MCP.Spawn)
  defmodule Attention, do: use(Facade, target: Server.Attention)
end
