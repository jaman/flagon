defmodule Flagon do
  @moduledoc """
  Terminal-based database query and analysis tool.
  """

  @spec start(keyword()) :: :ok | {:error, term()}
  def start(opts \\ []) do
    config = Flagon.Config.load(opts)
    Process.put(:flagon_config, config)
    Drafter.run(Flagon.App, title: "Flagon")
  end
end
