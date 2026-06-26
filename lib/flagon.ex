defmodule Flagon do
  @moduledoc """
  Terminal-based database query and analysis tool.
  """

  @spec start(keyword()) :: :ok | {:error, term()}
  def start(opts \\ []) do
    config = Flagon.Config.load(opts)
    Application.put_env(:flagon, :loaded_config, config)
    Drafter.run(Flagon.App, title: "Flagon", syntax_highlighting: true)
  end
end
