defmodule Server.MCP.Tool.RouteNeed do
  @moduledoc """
  Uqbar's verdicts on what waits on the operator (`Server.Office.Needs.settle/3`, `pass_up/4`): the
  caller's handle is passed down and only `uqbar`'s is honoured. Every seat sees these tools and
  every seat but Uqbar's is refused.
  """

  @doc "A verdict's result as the tool's reply."
  def reply(frame, key, :ok), do: Server.MCP.Tool.ok(frame, %{"key" => key, "recorded" => true})
  def reply(frame, _key, {:error, why}), do: Server.MCP.Tool.fail(frame, message(why))

  defp message(:forbidden), do: "only Uqbar's seat routes the operator's needs"
  defp message(:not_found), do: "no need waits under that key (operator_inbox lists them)"
  defp message(:always), do: "that need always reaches the operator, or is information: it takes no verdict"
  defp message(:no_recommendation), do: "a need passed up carries your recommendation"
end

defmodule Server.MCP.Tool.SettleNeed do
  @moduledoc "Uqbar settles a need without the operator: it leaves every surface for the day's digest."
  use Server.MCP.Tool

  schema do
    field :key, :string, required: true, description: "The need's key"
    field :why, :string, required: true, description: "How it is handled, for the operator's digest"
  end

  @impl true
  def execute(p, frame) do
    by = Identity.from_frame(frame).agent
    Server.MCP.Tool.RouteNeed.reply(frame, p.key, Server.Office.Needs.settle(p.key, p.why, by))
  end
end

defmodule Server.MCP.Tool.PassUpNeed do
  @moduledoc "Uqbar passes a need up to the operator, with its recommendation."
  use Server.MCP.Tool

  schema do
    field :key, :string, required: true, description: "The need's key"
    field :why, :string, required: true, description: "Why it needs the operator"
    field :recommendation, :string, required: true, description: "What you would do"
  end

  @impl true
  def execute(p, frame) do
    by = Identity.from_frame(frame).agent
    Server.MCP.Tool.RouteNeed.reply(frame, p.key, Server.Office.Needs.pass_up(p.key, p.why, p.recommendation, by))
  end
end
