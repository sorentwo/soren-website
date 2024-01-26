import Config

config :phoenix, :json_library, Jason

config :soren, Soren.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: Soren.ErrorHTML], layout: false],
  pubsub_server: Soren.PubSub,
  live_view: [signing_salt: "s3rU/IYC"]

config :tailwind,
  version: "3.3.5",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

import_config "#{config_env()}.exs"
