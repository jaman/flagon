defmodule Flagon.Connection.DuckDB do
  @moduledoc """
  DuckDB connection adapter using duckdbex directly.

  DuckDB doesn't use Ecto — it has its own native interface via duckdbex.
  """

  @behaviour Flagon.Connection

  @impl true
  def connect(config) do
    path = Map.get(config, :path, ":memory:")

    db_result =
      case path do
        ":memory:" -> Duckdbex.open()
        p -> Duckdbex.open(p)
      end

    with {:ok, db} <- db_result,
         {:ok, conn} <- Duckdbex.connection(db) do
      load_extensions(conn)
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

    case Duckdbex.query(conn, query_string) do
      {:ok, result_ref} ->
        columns = Duckdbex.columns(result_ref)
        rows = Duckdbex.fetch_all(result_ref)
        elapsed = System.monotonic_time(:millisecond) - started
        {:ok, build_result(columns, rows, elapsed)}

      {:error, reason} ->
        {:error, reason}
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

  @auto_extensions ["parquet", "json", "httpfs"]

  defp load_extensions(conn) do
    Enum.each(@auto_extensions, fn ext ->
      Duckdbex.query(conn, "INSTALL '#{ext}'")
      Duckdbex.query(conn, "LOAD '#{ext}'")
    end)
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
