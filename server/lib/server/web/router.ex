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
  end
end
