defmodule Soren.Router do
  use Phoenix.Router, helpers: false

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_root_layout, html: {Soren.Layouts, :root}
    plug :put_secure_browser_headers
  end

  scope "/", Soren do
    pipe_through :browser

    get "/", PageController, :index
    get "/blog", PageController, :blog
  end
end
