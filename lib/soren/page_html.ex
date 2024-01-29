defmodule Soren.PageHTML do
  use Soren.Web, :html

  def post_path(%{date: date, id: id}) do
    month = Calendar.strftime(date, "%m")
    day = Calendar.strftime(date, "%d")

    ~p"/#{date.year}/#{month}/#{day}/#{id}"
  end

  embed_templates "pages/*"
end
