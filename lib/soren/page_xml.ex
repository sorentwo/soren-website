defmodule Soren.PageXML do
  use Soren.Web, :xml

  embed_templates "pages/*", ext: ".xml"
end
