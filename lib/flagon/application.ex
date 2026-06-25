defmodule Flagon.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Flagon.Connection.Manager,
      {Cachex, [name: :flagon_history]},
      Flagon.Query.History
    ]

    opts = [strategy: :one_for_one, name: Flagon.Supervisor]
    result = Supervisor.start_link(children, opts)

    if Application.get_env(:flagon, :autostart, false) do
      spawn(&Flagon.start/0)
    end

    result
  end
end
