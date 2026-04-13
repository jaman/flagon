defmodule Flagon.Config do
  @moduledoc """
  Configuration loader with precedence: CLI args > .exs > .toml > defaults.
  """

  @config_dir Path.expand("~/.config/flagon")
  @exs_path Path.join(@config_dir, "config.exs")
  @toml_path Path.join(@config_dir, "config.toml")

  @defaults %{
    page_size: 1000,
    query_timeout_ms: 30_000,
    theme: "dracula",
    connections: []
  }

  @type connection_config :: %{
          name: String.t(),
          type: :kdb | :postgres | :duckdb,
          host: String.t() | nil,
          port: non_neg_integer() | nil,
          username: String.t() | nil,
          password: String.t() | nil,
          dsn: String.t() | nil,
          path: String.t() | nil
        }

  @type t :: %{
          page_size: non_neg_integer(),
          query_timeout_ms: non_neg_integer(),
          theme: String.t(),
          connections: [connection_config()]
        }

  @spec load(keyword()) :: t()
  def load(cli_opts \\ []) do
    file_config = load_file()
    merge(file_config, cli_opts)
  end

  @spec config_dir() :: String.t()
  def config_dir, do: @config_dir

  defp load_file do
    cond do
      File.exists?(@exs_path) -> Flagon.Config.Exs.load(@exs_path)
      File.exists?(@toml_path) -> Flagon.Config.Toml.load(@toml_path)
      true -> {:ok, %{}}
    end
    |> case do
      {:ok, config} -> config
      {:error, _reason} -> %{}
    end
  end

  defp merge(file_config, cli_opts) do
    cli_map = cli_to_map(cli_opts)

    @defaults
    |> Map.merge(normalize(file_config))
    |> Map.merge(normalize(cli_map))
  end

  defp cli_to_map(opts) do
    opts
    |> Enum.reduce(%{}, fn
      {:connection, conn_string}, acc ->
        case parse_connection_string(conn_string) do
          {:ok, conn} -> Map.update(acc, :connections, [conn], &[conn | &1])
          _ -> acc
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp normalize(config) when is_map(config) do
    config
    |> normalize_connections()
    |> Map.take([:page_size, :query_timeout_ms, :theme, :connections])
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalize_connections(%{connections: conns} = config) when is_list(conns) do
    normalized =
      Enum.map(conns, fn conn ->
        conn
        |> normalize_keys()
        |> normalize_type()
      end)

    %{config | connections: normalized}
  end

  defp normalize_connections(config), do: config

  defp normalize_keys(conn) when is_map(conn) do
    Map.new(conn, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
  end

  defp normalize_type(%{type: type} = conn) when is_binary(type) do
    %{conn | type: String.to_atom(type)}
  end

  defp normalize_type(conn), do: conn

  @spec parse_connection_string(String.t()) :: {:ok, connection_config()} | {:error, String.t()}
  def parse_connection_string(conn_string) do
    case String.split(conn_string, "://", parts: 2) do
      ["kdb", rest] -> parse_kdb_connection(rest)
      ["postgres", _rest] -> {:ok, %{name: conn_string, type: :postgres, dsn: conn_string}}
      ["duckdb", path] -> {:ok, %{name: path, type: :duckdb, path: path}}
      _ -> {:error, "unrecognized connection format: #{conn_string}"}
    end
  end

  defp parse_kdb_connection(rest) do
    uri = URI.parse("kdb://#{rest}")

    {:ok,
     %{
       name: uri.host || "localhost",
       type: :kdb,
       host: uri.host || "localhost",
       port: uri.port || 5001,
       username: uri.userinfo && String.split(uri.userinfo, ":") |> List.first(),
       password: uri.userinfo && String.split(uri.userinfo, ":") |> List.last()
     }}
  end
end
