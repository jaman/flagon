defmodule Flagon.Schema.Postgres do
  @moduledoc """
  PostgreSQL schema introspection via information_schema.
  """

  @spec introspect(module()) :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def introspect(repo) do
    with {:ok, schemas} <- list_schemas(repo),
         nodes <- Enum.map(schemas, fn schema -> build_schema_node(repo, schema) end) do
      {:ok, nodes}
    end
  end

  defp list_schemas(repo) do
    sql = """
    SELECT schema_name FROM information_schema.schemata
    WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
    ORDER BY schema_name
    """

    case Ecto.Adapters.SQL.query(repo, sql, []) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn [name] -> name end)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_schema_node(repo, schema_name) do
    tables = list_tables(repo, schema_name)
    views = list_views(repo, schema_name)

    %{
      id: {:schema, schema_name},
      label: schema_name,
      type: :namespace,
      children: tables ++ views,
      metadata: %{schema: schema_name}
    }
  end

  defp list_tables(repo, schema_name) do
    sql = """
    SELECT table_name FROM information_schema.tables
    WHERE table_schema = $1 AND table_type = 'BASE TABLE'
    ORDER BY table_name
    """

    case Ecto.Adapters.SQL.query(repo, sql, [schema_name]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [table_name] ->
          columns = list_columns(repo, schema_name, table_name)

          %{
            id: {:table, schema_name, table_name},
            label: table_name,
            type: :table,
            children: columns,
            metadata: %{schema: schema_name, table: table_name, kind: :table}
          }
        end)

      _ ->
        []
    end
  end

  defp list_views(repo, schema_name) do
    sql = """
    SELECT table_name FROM information_schema.views
    WHERE table_schema = $1
    ORDER BY table_name
    """

    case Ecto.Adapters.SQL.query(repo, sql, [schema_name]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [view_name] ->
          columns = list_columns(repo, schema_name, view_name)

          %{
            id: {:table, schema_name, view_name},
            label: "#{view_name} (view)",
            type: :table,
            children: columns,
            metadata: %{schema: schema_name, table: view_name, kind: :view}
          }
        end)

      _ ->
        []
    end
  end

  defp list_columns(repo, schema_name, table_name) do
    sql = """
    SELECT column_name, data_type, is_nullable, column_default,
           ordinal_position
    FROM information_schema.columns
    WHERE table_schema = $1 AND table_name = $2
    ORDER BY ordinal_position
    """

    case Ecto.Adapters.SQL.query(repo, sql, [schema_name, table_name]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [col_name, data_type, nullable, default, _pos] ->
          nullable_str = if nullable == "YES", do: "?", else: ""
          default_str = if default, do: " = #{default}", else: ""

          %{
            id: {:col, schema_name, table_name, col_name},
            label: "#{col_name} : #{data_type}#{nullable_str}#{default_str}",
            type: :column,
            children: [],
            metadata: %{
              column: col_name,
              data_type: data_type,
              nullable: nullable == "YES",
              default: default
            }
          }
        end)

      _ ->
        []
    end
  end
end
