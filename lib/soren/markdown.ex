defmodule Soren.Markdown do
  @moduledoc false

  @options [
    extension: [autolink: true, table: true],
    features: [syntax_highlight_theme: "nord"]
  ]

  def convert(_filepath, body, _attrs, _opts) do
    MDEx.to_html(body, @options)
  end
end
