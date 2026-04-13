defmodule Flagon.Connection.Postgres do
  @moduledoc """
  PostgreSQL connection adapter using dynamic Ecto repos.
  `conn` is the repo module atom returned by connect/1.
  """

  @behaviour Flagon.Connection

  @impl true
  def connect(config) do
    repo_opts = build_repo_opts(config)
    name = to_string(config.name)

    Flagon.Connection.EctoAdapter.create_and_start_repo(
      name,
      Ecto.Adapters.Postgres,
      repo_opts
    )
  end

  @impl true
  def disconnect(conn) when is_atom(conn) do
    try do
      conn.stop()
    catch
      _, _ -> :ok
    end

    :ok
  end

  def disconnect(_conn), do: :ok

  @impl true
  def query(repo, query_string) when is_atom(repo) do
    started = System.monotonic_time(:millisecond)

    case Ecto.Adapters.SQL.query(repo, query_string, []) do
      {:ok, result} ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, Flagon.Query.Result.from_ecto(result, elapsed)}

      {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def query(repo, query_string, params) when is_atom(repo) do
    started = System.monotonic_time(:millisecond)

    case Ecto.Adapters.SQL.query(repo, query_string, params) do
      {:ok, result} ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, Flagon.Query.Result.from_ecto(result, elapsed)}

      {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
        {:error, msg}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def introspect(repo) when is_atom(repo) do
    Flagon.Schema.Postgres.introspect(repo)
  end

  @impl true
  def stream_query(repo, query_string, opts) when is_atom(repo) do
    max_rows = Keyword.get(opts, :max_rows, 1000)

    result =
      repo.transaction(fn ->
        Ecto.Adapters.SQL.stream(repo, query_string, [], max_rows: max_rows)
        |> Enum.to_list()
      end)

    case result do
      {:ok, chunks} -> {:ok, chunks}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_repo_opts(config) do
    base =
      case Map.get(config, :dsn) do
        nil -> build_from_fields(config)
        dsn -> [url: dsn]
      end

    Keyword.merge(base,
      pool_size: Map.get(config, :pool_size, 5),
      show_sensitive_data_on_connection_error: true
    )
  end

  defp build_from_fields(config) do
    [
      hostname: Map.get(config, :host, "localhost"),
      port: Map.get(config, :port, 5432),
      database: Map.get(config, :database, "postgres"),
      username: Map.get(config, :username, "postgres"),
      password: Map.get(config, :password, "")
    ]
  end
end
