defmodule Soren.Blog do
  @moduledoc false

  use NimblePublisher,
    build: Soren.Blog.Post,
    from: "priv/posts/*.md",
    as: :posts,
    html_converter: Soren.Markdown,
    highlighters: []

  @posts Enum.sort_by(@posts, & &1.date, {:desc, Date})

  def all_posts, do: @posts

  def get_post(id) do
    case Enum.find(all_posts(), &(&1.id == id)) do
      nil -> :error
      article -> {:ok, article}
    end
  end
end
