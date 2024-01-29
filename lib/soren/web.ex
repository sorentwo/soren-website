defmodule Soren.Web do
  @moduledoc false

  defmacro embed_templates(pattern, opts) do
    quote do
      require Phoenix.Template

      Phoenix.Template.compile_all(
        &(&1 |> Path.basename() |> Path.rootname() |> Path.rootname()),
        Path.expand(unquote(opts)[:root] || __DIR__, __DIR__),
        unquote(pattern) <> unquote(opts)[:ext]
      )
    end
  end

  def static_paths, do: ~w(assets fonts images favicon.svg robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller,
        formats: [:html, :xml],
        layouts: [html: Soren.Layouts]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller, only: [current_url: 1, view_module: 1, view_template: 1]
      import Phoenix.HTML

      unquote(verified_routes())
    end
  end

  def xml do
    quote do
      import Soren.Web, only: [embed_templates: 2]
      import Phoenix.HTML

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: Soren.Endpoint,
        router: Soren.Router,
        statics: Soren.Web.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
