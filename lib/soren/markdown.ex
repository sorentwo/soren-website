defmodule Soren.Markdown do
  @moduledoc false

  def convert(_filepath, body, _attrs, _opts) do
    MDEx.to_html(body, [])
  end
end
