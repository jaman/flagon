defmodule Flagon.Config.Exs do
  @moduledoc """
  Elixir script configuration file evaluator.
  """

  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(path) do
    {result, _bindings} = Code.eval_file(path)

    case result do
      %{} = config -> {:ok, config}
      _ -> {:error, "config.exs must return a map"}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end
end
