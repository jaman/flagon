defmodule Flagon.Schema.Postgres do
  @moduledoc """
  PostgreSQL schema introspection via information_schema.
  """

  @spec introspect(term()) :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def introspect(_conn) do
    {:error, :not_yet_implemented}
  end
end
