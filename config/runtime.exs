import Config

if config_env() == :prod do
  config :soren, Soren.Endpoint,
    server: true,
    url: [host: "sorentwo.com", port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "8000")
    ]
end
