defmodule Soren.ErrorHTML do
  use Soren.Web, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
