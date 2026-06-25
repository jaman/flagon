defmodule Flagon.Connection do
  @moduledoc """
  Behaviour for database connection adapters.
  """

  @type conn :: pid() | atom()
  @type query_result :: {:ok, Flagon.Query.Result.t()} | {:error, term()}
  @type schema_tree :: [Flagon.Schema.schema_node()]

  @callback connect(config :: map()) :: {:ok, conn()} | {:error, term()}
  @callback disconnect(conn()) :: :ok
  @callback query(conn(), query :: String.t()) :: query_result()
  @callback query(conn(), query :: String.t(), params :: list()) :: query_result()
  @callback introspect(conn()) :: {:ok, schema_tree()} | {:error, term()}
  @callback stream_query(conn(), query :: String.t(), opts :: keyword()) ::
              {:ok, Enumerable.t()} | {:error, term()}
  @callback load_columns(conn(), namespace :: String.t(), table :: String.t()) :: schema_tree()

  @optional_callbacks load_columns: 3

  @spec adapter_for(atom()) :: module()
  def adapter_for(:kdb), do: Flagon.Connection.Kdb
  def adapter_for(:postgres), do: Flagon.Connection.Postgres
  def adapter_for(:duckdb), do: Flagon.Connection.DuckDB
end
