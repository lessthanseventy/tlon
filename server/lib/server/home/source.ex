defmodule Server.Home.Source do
  @moduledoc """
  An outside source of proposals (`Server.Proposal`) for the operator's personal life; `Server.Home.Source.Mail` and `Server.Home.Source.Bank` are the ones there are.
  A source answers its `name/0` (the `source` of what it offers and the word in the `home_sources`
  setting), `fetch/0` and `auto/0`; `Server.Home.Sources` polls the enabled ones and hands what
  `fetch/0` returns to `Server.Proposal.offer/5` and `Server.Proposal.resolve/3`.
  """

  @doc ~s(The source's name: `"mail"`, `"bank"`.)
  @callback name() :: String.t()

  @doc """
  What the source suggests now: `{:ok, proposals, resolved}`, `proposals` as `Server.Proposal.offer/5`
  takes them, `resolved` what it knows is gone (a review done elsewhere) as
  `Server.Proposal.resolve/3` takes it, or `{:error, reason}`: a failure leaves everything already
  proposed alone.
  """
  @callback fetch() :: {:ok, [map()], [String.t() | {String.t(), String.t() | :drop}]} | {:error, term()}

  @doc ~s{The kinds of proposal (`"waiting"`, `"todo"`) the operator trusts this source to file without a yes: facts, not asks.}
  @callback auto() :: [String.t()]

  @doc """
  Called by `Server.Home.Sources` after what `fetch/0` returned was filed (`offer` and `resolve`
  returned): a source that keeps a position moves it here, so a fetch whose filing failed is made again.
  """
  @callback kept() :: :ok

  @optional_callbacks kept: 0
end
