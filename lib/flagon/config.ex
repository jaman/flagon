defmodule Flagon.Config do
  @moduledoc """
  Configuration loader with precedence: CLI args > .exs > .toml > defaults.
  """

  @default_config_dir Path.expand("~/.config/flagon")

  @defaults %{
    page_size: 1000,
    query_timeout_ms: 30_000,
    theme: "dracula",
    connections: []
  }

  @type connection_config :: %{
          name: String.t(),
          type: :kdb | :postgres | :duckdb,
          folder: String.t() | nil,
          host: String.t() | nil,
          port: non_neg_integer() | nil,
          username: String.t() | nil,
          password: String.t() | nil,
          tls: boolean() | nil,
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

    file_config
    |> merge(cli_opts)
    |> merge_server_list(cli_opts)
  end

  @spec load_server_list(String.t()) :: [connection_config()]
  def load_server_list(path) do
    expanded = Path.expand(path)

    case File.read(expanded) do
      {:ok, content} -> parse_server_list(expanded, content)
      {:error, _reason} -> []
    end
  end

  @spec config_dir() :: String.t()
  def config_dir, do: Application.get_env(:flagon, :config_dir) || @default_config_dir

  @doc """
  The unique, folder-qualified identity of a connection: `folder/name`, or the
  bare `name` when the connection has no folder.
  """
  @spec qualified_name(connection_config() | map()) :: String.t()
  def qualified_name(%{folder: folder, name: name}) when is_binary(folder) and folder != "" do
    folder <> "/" <> to_string(name)
  end

  def qualified_name(%{name: name}), do: to_string(name)

  @spec save(t(), keyword()) :: :ok | {:error, term()}
  def save(config, opts \\ []) do
    dir = Keyword.get(opts, :dir, config_dir())
    File.mkdir_p!(dir)
    persistable = Map.take(config, [:page_size, :query_timeout_ms, :theme, :connections])
    exs_path = Path.join(dir, "config.exs")

    if File.exists?(exs_path) do
      File.write(exs_path, inspect(persistable, pretty: true, limit: :infinity))
    else
      File.write(Path.join(dir, "config.toml"), Flagon.Config.Toml.encode(persistable))
    end
  end

  defp load_file do
    exs_path = Path.join(config_dir(), "config.exs")
    toml_path = Path.join(config_dir(), "config.toml")

    cond do
      File.exists?(exs_path) -> Flagon.Config.Exs.load(exs_path)
      File.exists?(toml_path) -> Flagon.Config.Toml.load(toml_path)
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

  defp merge_server_list(config, cli_opts) do
    path = cli_opts[:servers] || Map.get(config, :server_list)

    case path && load_server_list(path) do
      servers when is_list(servers) and servers != [] ->
        %{config | connections: config.connections ++ servers}

      _ ->
        config
    end
  end

  defp parse_server_list(path, content) do
    if String.ends_with?(path, ".json") do
      Flagon.Config.ServerList.parse_json(content)
    else
      Flagon.Config.ServerList.parse_text(content)
    end
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
    |> Map.take([:page_size, :query_timeout_ms, :theme, :connections, :server_list])
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
