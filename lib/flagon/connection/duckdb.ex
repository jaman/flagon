defmodule Flagon.Connection.DuckDB do
  @moduledoc """
  DuckDB connection adapter using duckdbex directly.

  DuckDB doesn't use Ecto — it has its own native interface via duckdbex.
  """

  @behaviour Flagon.Connection

  @impl true
  def connect(config) do
    path = Map.get(config, :path, ":memory:")
    path_charlist = String.to_charlist(path)

    with {:ok, db} <- Duckdbex.open(path_charlist),
         {:ok, conn} <- Duckdbex.connection(db) do
      name = to_string(config.name)
      register(name, %{db: db, conn: conn, path: path})
      {:ok, conn}
    end
  end

  @impl true
  def disconnect(conn) do
    case find_by_conn(conn) do
      {name, _state} -> unregister(name)
      nil -> :ok
    end

    :ok
  end

  @impl true
  def query(conn, query_string) do
    query(conn, query_string, [])
  end

  @impl true
  def query(conn, query_string, _params) do
    started = System.monotonic_time(:millisecond)

    with {:ok, result_ref} <- Duckdbex.query(conn, query_string),
         columns <- Duckdbex.columns(result_ref),
         {:ok, rows} <- fetch_all_rows(result_ref) do
      elapsed = System.monotonic_time(:millisecond) - started
      {:ok, build_result(columns, rows, elapsed)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def introspect(conn) do
    Flagon.Schema.DuckDB.introspect(conn)
  end

  @impl true
  def stream_query(_conn, _query_string, _opts) do
    {:error, :not_yet_implemented}
  end

  defp fetch_all_rows(result_ref) do
    fetch_all_rows(result_ref, [])
  end

  defp fetch_all_rows(result_ref, acc) do
    case Duckdbex.fetch_chunk(result_ref) do
      {:ok, []} -> {:ok, Enum.reverse(acc) |> List.flatten()}
      {:ok, chunk} -> fetch_all_rows(result_ref, [chunk | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_result(columns, rows, elapsed) do
    col_specs =
      Enum.map(columns, fn name ->
        %{name: to_string(name), type: :unknown}
      end)

    typed_cols =
      case rows do
        [first_row | _] ->
          Enum.zip(col_specs, first_row)
          |> Enum.map(fn {col, val} -> %{col | type: infer_type(val)} end)

        [] ->
          col_specs
      end

    %Flagon.Query.Result{
      columns: typed_cols,
      rows: rows,
      row_count: length(rows),
      execution_time_ms: elapsed
    }
  end

  defp infer_type(nil), do: :unknown
  defp infer_type(v) when is_integer(v), do: :integer
  defp infer_type(v) when is_float(v), do: :float
  defp infer_type(v) when is_boolean(v), do: :boolean
  defp infer_type(v) when is_binary(v), do: :string
  defp infer_type(_), do: :unknown

  @registry :flagon_duckdb_conns

  defp ensure_registry do
    if :ets.whereis(@registry) == :undefined do
      :ets.new(@registry, [:named_table, :public, :set])
    end
  end

  defp register(name, state) do
    ensure_registry()
    :ets.insert(@registry, {name, state})
  end

  defp unregister(name) do
    ensure_registry()
    :ets.delete(@registry, name)
  end

  defp find_by_conn(conn) do
    ensure_registry()

    :ets.foldl(
      fn {name, %{conn: c} = state}, acc ->
        if c == conn, do: {name, state}, else: acc
      end,
      nil,
      @registry
    )
  end
end
