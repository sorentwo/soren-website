defmodule Soren.PageController do
  use Soren.Web, :controller

  def index(conn, _params) do
    conn
    |> assign(:page_title, "Home")
    |> render(:index)
  end
end
