defmodule Soren.Endpoint do
  use Phoenix.Endpoint, otp_app: :soren

  plug Plug.Static,
    at: "/",
    from: :soren,
    brotli: true,
    gzip: true,
    only: Soren.Web.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket

    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Logster.Plug
  plug Soren.Router
end
