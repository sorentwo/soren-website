defmodule Soren.Application do
  @moduledoc false

  use Application

  @impl Application
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Soren.PubSub},
      Soren.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Soren.Supervisor)
  end

  @impl Application
  def config_change(changed, _new, removed) do
    Soren.Endpoint.config_change(changed, removed)

    :ok
  end
end
