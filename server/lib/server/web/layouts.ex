defmodule Server.Web.Layouts do
  @moduledoc """
  The root layout: the palette as CSS variables, inlined from ficciones' rendered
  `~/.config/ficciones/theme/web.css` (roles, never hues — the same file the theme toggle
  repoints), a fallback of uqbar's roles when the file is absent (a clone without ficciones),
  and Phoenix's + LiveView's bundled JS.
  """
  use Phoenix.Component

  @fallback """
  :root { --ground:#000000; --panel:#0D0D0D; --card:#0E0E0E; --raised:#1A1A1A; --edge:#2A2A2A; --body:#FFB000; --key:#33C7FF; --meta:#B4A5D6; --prose:#C7C7C7; --inactive:#B8994C; --live:#33FF00; --done:#62A562; --attention:#F06CB4; --alarm:#FF6969; --assistant:#B98AFF; --warn:#FF6E06; --cursor-field:#FFB000; --sel-field:#C7B6E8; --sel-ink:#1A0A2E; --field-ink:#0A0A0A; --structure:#B5651D; --user-voice:#33FF00; --assistant-voice:#FFB000; --font:"ComicShannsMono Nerd Font", monospace; }
  """

  def palette_css do
    path = Path.expand("~/.config/ficciones/theme/web.css")

    case File.read(path) do
      {:ok, css} -> css
      _ -> @fallback
    end
  end

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>tlön</title>
        <%!-- HEEx keeps `{}` literal inside style/script (JS braces), so these interpolate with <%= %> --%>
        <style><%= Phoenix.HTML.raw(palette_css()) %></style>
        <style><%= Phoenix.HTML.raw(Server.Web.Styles.css()) %></style>
        <script defer src="/phoenix/phoenix.min.js"></script>
        <script defer src="/live-view/phoenix_live_view.min.js"></script>
        <script>
          window.addEventListener("DOMContentLoaded", () => {
            const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content");
            const socket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, { params: { _csrf_token: csrf } });
            socket.connect();
            window.liveSocket = socket;
          });
        </script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end
