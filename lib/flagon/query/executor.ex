defmodule Flagon.Query.Executor do
  @moduledoc """
  Async query execution with timeout and cancellation.
  """

  @spec execute_async(pid(), String.t(), keyword()) :: Task.t()
  def execute_async(caller, query_string, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    Task.async(fn ->
      task =
        Task.async(fn ->
          Flagon.Connection.Manager.query(query_string)
        end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} ->
          send(caller, {:query_complete, result})

        nil ->
          send(caller, {:query_complete, {:error, :timeout}})
      end
    end)
  end

  @spec execute_sync(String.t(), keyword()) :: Flagon.Connection.query_result()
  def execute_sync(query_string, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    task =
      Task.async(fn ->
        Flagon.Connection.Manager.query(query_string)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :timeout}
    end
  end
end
