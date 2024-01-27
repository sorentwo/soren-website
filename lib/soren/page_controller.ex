defmodule Soren.PageController do
  use Soren.Web, :controller

  def index(conn, _params) do
    conn
    |> assign(:page_title, "Home")
    |> assign(:page_theme, :dark)
    |> render(:index)
  end

  def blog(conn, _params) do
    conn
    |> assign(:page_title, "Articles")
    |> assign(:posts, Soren.Blog.all_posts())
    |> render(:blog)
  end

  def post(conn, %{"id" => id}) do
    case Soren.Blog.get_post(id) do
      {:ok, post} ->
        conn
        |> assign(:page_title, post.title)
        |> assign(:post, post)
        |> render(:post)

      _ ->
        redirect(conn, to: "/blog")
    end
  end
end
