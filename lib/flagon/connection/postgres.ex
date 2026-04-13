defmodule Flagon.Connection.Postgres do
  @moduledoc """
  PostgreSQL connection adapter using dynamic Ecto repos.
  """

  @behaviour Flagon.Connection

  @impl true
  def connect(_config) do
    {:error, :not_yet_implemented}
  end

  @impl true
  def disconnect(_conn) do
    :ok
  end

  @impl true
  def query(_conn, _query_string) do
    {:error, :not_yet_implemented}
  end

  @impl true
  def query(_conn, _query_string, _params) do
    {:error, :not_yet_implemented}
  end

  @impl true
  def introspect(_conn) do
    {:error, :not_yet_implemented}
  end

  @impl true
  def stream_query(_conn, _query_string, _opts) do
    {:error, :not_yet_implemented}
  end
end
