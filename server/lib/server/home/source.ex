defmodule Server.Home.Source do
  @moduledoc """
  An outside source of proposals (`Server.Proposal`): GitHub now, Jira, Slack and mail the same way.
  A source answers its `name/0` (the `source` of what it offers and the word in the `home_sources`
  setting), `fetch/0` and `auto/0`; `Server.Home.Sources` polls the enabled ones and hands what
  `fetch/0` returns to `Server.Proposal.offer/5` and `Server.Proposal.resolve/3`.
  """

  @doc "The source's name: `\"github\"`."
  @callback name() :: String.t()

  @doc """
  What the source suggests now: `{:ok, proposals, resolved}`, `proposals` as `Server.Proposal.offer/5`
  takes them, `resolved` what it knows is gone (a PR merged, a review done elsewhere) as
  `Server.Proposal.resolve/3` takes it, or `{:error, reason}`: a failure leaves everything already
  proposed alone.
  """
  @callback fetch() :: {:ok, [map()], [String.t() | {String.t(), String.t() | :drop}]} | {:error, term()}

  @doc ~s{The kinds of proposal (`"waiting"`, `"todo"`) the operator trusts this source to file without a yes: facts, not asks.}
  @callback auto() :: [String.t()]
end
