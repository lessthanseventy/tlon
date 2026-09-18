defmodule Server.Web.Endpoint do
  @moduledoc """
  The web UI's door (one-brain piece D): a second loopback Bandit listener beside the MCP
  channel's, serving one LiveView over the SAME `Server.*` contexts and `Server.Bus` the TUI and
  asterion read. Static files are Phoenix's and LiveView's own bundled JS from their priv dirs —
  no asset pipeline; the page's CSS is the palette, rendered by ficciones and inlined.
  """
  use Phoenix.Endpoint, otp_app: :server

  @session_options [store: :cookie, key: "_tlon_web", signing_salt: "tlon-web-session", same_site: "Lax"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  plug(Plug.Static, at: "/phoenix", from: :phoenix, gzip: false, only: ~w(phoenix.min.js))
  plug(Plug.Static, at: "/live-view", from: :phoenix_live_view, gzip: false, only: ~w(phoenix_live_view.min.js))

  plug(Plug.Parsers, parsers: [:urlencoded, :multipart, :json], pass: ["*/*"], json_decoder: JSON)
  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(Plug.Session, @session_options)
  plug(Server.Web.Router)
end
