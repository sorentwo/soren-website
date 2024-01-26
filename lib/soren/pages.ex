defmodule Soren.Pages do
  use Soren.Web, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
