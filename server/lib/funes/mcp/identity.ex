defmodule Server.MCP.Identity do
  @moduledoc """
  Who a tool call IS: the binding the validator attached to this connection,
  read from the frame — never from a call parameter, so misdirection is
  unrepresentable (pi doc §2a). Resolving also bumps the session's warmth: a
  tool call arriving at funes is OBSERVABLE activity, measured here rather than
  self-reported by a heartbeat (§4 measure-don't-log) — which is why every tool
  resolves identity through this one door.
  """
  alias Anubis.Server.Frame
  alias Server.Staff

  @type t :: %{
          thread_id: integer(),
          agent_id: integer(),
          agent: String.t(),
          session_id: integer() | nil,
          token: String.t()
        }

  @spec from_frame(Frame.t()) :: t()
  def from_frame(frame) do
    raw = Frame.authorization(frame).raw_claims

    identity = %{
      thread_id: raw["thread_id"],
      agent_id: raw["agent_id"],
      agent: raw["sub"],
      session_id: raw["session_id"],
      token: raw["token"]
    }

    touch(identity)
    identity
  end

  # No session until register claims one — nothing to keep warm yet.
  defp touch(%{session_id: nil}), do: :ok

  defp touch(%{session_id: id}) do
    Staff.touch_sessions([id], DateTime.truncate(DateTime.utc_now(), :second))
  end
end
