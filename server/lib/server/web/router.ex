defmodule Server.Web.Router do
  @moduledoc false
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Server.Web.Layouts, :root})
    plug(:protect_from_forgery)
  end

  scope "/", Server.Web do
    pipe_through(:browser)

    live("/", HomeLive, :index)
    live("/threads/:id", HomeLive, :thread)
    # the other panels (D/2): one LiveView, the action names the panel
    live("/triage", PanelsLive, :triage)
    live("/roster", PanelsLive, :roster)
    live("/tickets", PanelsLive, :tickets)
    live("/health", PanelsLive, :health)
  end
end
