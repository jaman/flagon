defmodule Flagon.Config.Toml do
  @moduledoc """
  TOML configuration file parser.
  """

  @default_fields [:page_size, :query_timeout_ms, :theme]
  @connection_fields [:name, :type, :folder, :host, :port, :username, :password, :tls, :dsn, :path]

  @spec load(String.t()) :: {:ok, map()} | {:error, term()}
  def load(path) do
    case Toml.decode_file(path) do
      {:ok, raw} -> {:ok, transform(raw)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Serializes a config map to a TOML string with a `[defaults]` table and one
  `[[connections]]` array-of-tables entry per connection. Nil fields are omitted.
  """
  @spec encode(map()) :: String.t()
  def encode(config) do
    defaults = encode_defaults(config)
    connections = encode_connections(Map.get(config, :connections, []))

    (defaults ++ connections)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
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

  defp encode_defaults(config) do
    case encode_fields(config, @default_fields) do
      [] -> []
      lines -> ["[defaults]" | lines]
    end
  end

  defp encode_connections(conns) when is_list(conns) do
    Enum.flat_map(conns, fn conn -> ["", "[[connections]]" | encode_fields(conn, @connection_fields)] end)
  end

  defp encode_connections(_conns), do: []

  defp encode_fields(source, fields) do
    fields
    |> Enum.map(fn key -> encode_kv(key, Map.get(source, key)) end)
    |> Enum.reject(&is_nil/1)
  end

  defp encode_kv(_key, nil), do: nil
  defp encode_kv(key, value), do: "#{key} = #{encode_value(value)}"

  defp encode_value(value) when is_integer(value), do: Integer.to_string(value)
  defp encode_value(value) when is_boolean(value), do: to_string(value)
  defp encode_value(value) when is_float(value), do: Float.to_string(value)
  defp encode_value(value) when is_atom(value), do: ~s("#{escape(Atom.to_string(value))}")
  defp encode_value(value) when is_binary(value), do: ~s("#{escape(value)}")

  defp escape(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
