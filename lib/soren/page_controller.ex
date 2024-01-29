defmodule Soren.PageController do
  use Soren.Web, :controller

  alias Soren.Blog

  def index(conn, _params) do
    conn
    |> assign(:page_title, "Home")
    |> assign(:page_dark?, true)
    |> assign(:posts, Blog.all_posts())
    |> render(:index)
  end

  def feed(conn, _params) do
    posts = Blog.all_posts()

    updated =
      posts
      |> Enum.map(& &1.date)
      |> Enum.sort({:desc, Date})
      |> List.first()

    conn
    |> assign(:posts, posts)
    |> assign(:updated, updated)
    |> render("feed.xml", layout: false)
  end

  def post(conn, %{"id" => id}) do
    case Blog.get_post(id) do
      {:ok, post} ->
        conn
        |> assign(:page_description, post.summary)
        |> assign(:page_title, post.title)
        |> assign(:post, post)
        |> render(:post)

      _ ->
        redirect(conn, to: "/blog")
    end
  end
end
