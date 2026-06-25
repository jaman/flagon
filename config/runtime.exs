import Config

if config_env() == :prod do
  config :flagon, autostart: true
end
