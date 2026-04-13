defmodule Flagon.Schema.DuckDB do
  @moduledoc """
  DuckDB schema introspection via information_schema.
  """

  @spec introspect(reference()) :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def introspect(conn) do
    with {:ok, schemas} <- list_schemas(conn) do
      nodes = Enum.map(schemas, fn schema -> build_schema_node(conn, schema) end)
      {:ok, nodes}
    end
  end

  defp list_schemas(conn) do
    sql = """
    SELECT schema_name FROM information_schema.schemata
    WHERE schema_name NOT IN ('pg_catalog', 'information_schema')
    ORDER BY schema_name
    """

    case run_query(conn, sql) do
      {:ok, rows} -> {:ok, Enum.map(rows, fn [name] -> name end)}
      error -> error
    end
  end

  defp build_schema_node(conn, schema_name) do
    tables = list_tables(conn, schema_name)

    %{
      id: {:schema, schema_name},
      label: schema_name,
      type: :namespace,
      children: tables,
      metadata: %{schema: schema_name}
    }
  end

  defp list_tables(conn, schema_name) do
    sql = """
    SELECT table_name, table_type FROM information_schema.tables
    WHERE table_schema = '#{escape(schema_name)}'
    ORDER BY table_name
    """

    case run_query(conn, sql) do
      {:ok, rows} ->
        Enum.map(rows, fn [table_name, table_type] ->
          columns = list_columns(conn, schema_name, table_name)
          kind_label = if table_type == "VIEW", do: " (view)", else: ""

          %{
            id: {:table, schema_name, table_name},
            label: "#{table_name}#{kind_label}",
            type: :table,
            children: columns,
            metadata: %{schema: schema_name, table: table_name, kind: String.downcase(table_type)}
          }
        end)

      _ ->
        []
    end
  end

  defp list_columns(conn, schema_name, table_name) do
    sql = """
    SELECT column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_schema = '#{escape(schema_name)}'
      AND table_name = '#{escape(table_name)}'
    ORDER BY ordinal_position
    """

    case run_query(conn, sql) do
      {:ok, rows} ->
        Enum.map(rows, fn [col_name, data_type, nullable] ->
          nullable_str = if nullable == "YES", do: "?", else: ""

          %{
            id: {:col, schema_name, table_name, col_name},
            label: "#{col_name} : #{data_type}#{nullable_str}",
            type: :column,
            children: [],
            metadata: %{column: col_name, data_type: data_type, nullable: nullable == "YES"}
          }
        end)

      _ ->
        []
    end
  end

  defp run_query(conn, sql) do
    with {:ok, result_ref} <- Duckdbex.query(conn, sql),
         {:ok, rows} <- fetch_all(result_ref) do
      {:ok, rows}
    end
  end

  defp fetch_all(result_ref) do
    fetch_all(result_ref, [])
  end

  defp fetch_all(result_ref, acc) do
    case Duckdbex.fetch_chunk(result_ref) do
      {:ok, []} -> {:ok, Enum.reverse(acc) |> List.flatten()}
      {:ok, chunk} -> fetch_all(result_ref, [chunk | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  defp escape(str), do: String.replace(str, "'", "''")
end
