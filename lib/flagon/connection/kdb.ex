defmodule Flagon.Connection.Kdb do
  @moduledoc """
  KDB+/q connection adapter using ExeQute.
  """

  @behaviour Flagon.Connection

  @impl true
  def connect(config) do
    opts =
      [
        host: Map.get(config, :host, "localhost"),
        port: Map.get(config, :port, 5001)
      ]
      |> maybe_add(:username, config)
      |> maybe_add(:password, config)

    ExeQute.connect(opts)
  end

  @impl true
  def disconnect(conn) do
    ExeQute.disconnect(conn)
    :ok
  end

  @impl true
  def query(conn, query_string) do
    started = System.monotonic_time(:millisecond)

    case ExeQute.query(conn, query_string) do
      {:ok, rows} when is_list(rows) ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, Flagon.Query.Result.from_maps(rows, elapsed)}

      {:ok, scalar} ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, Flagon.Query.Result.from_scalar(scalar, elapsed)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def query(conn, query_string, params) do
    started = System.monotonic_time(:millisecond)

    case ExeQute.query(conn, query_string, params) do
      {:ok, rows} when is_list(rows) ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, Flagon.Query.Result.from_maps(rows, elapsed)}

      {:ok, scalar} ->
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, Flagon.Query.Result.from_scalar(scalar, elapsed)}

      {:error, _} = error ->
        error
    end
  end

  @impl true
  def introspect(conn) do
    Flagon.Schema.Kdb.introspect(conn)
  end

  @impl true
  def stream_query(_conn, _query_string, _opts) do
    {:error, :not_supported}
  end

  defp maybe_add(opts, key, config) do
    case Map.get(config, key) do
      blank when blank in [nil, ""] -> opts
      value -> Keyword.put(opts, key, value)
    end
  end
end
