defmodule Flagon.Config.Toml do
  @moduledoc """
  TOML configuration file parser.
  """

  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(path) do
    case Toml.decode_file(path) do
      {:ok, raw} -> {:ok, transform(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp transform(raw) do
    defaults =
      raw
      |> Map.get("defaults", %{})
      |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)

    connections =
      raw
      |> Map.get("connections", [])
      |> Enum.map(fn conn ->
        Map.new(conn, fn {k, v} -> {String.to_atom(k), v} end)
      end)

    Map.merge(defaults, %{connections: connections})
  end
end
