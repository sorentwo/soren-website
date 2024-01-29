defmodule Soren.PageXML do
  use Soren.Web, :xml

  import Soren.PageHTML, only: [post_path: 1]

  embed_templates "pages/*", ext: ".xml"
end
