defmodule Flagon.Query.History do
  @moduledoc """
  Persisted query history backed by DETS.
  """

  use GenServer

  @max_entries 500
  @table_name :flagon_history
  @history_dir Path.expand("~/.config/flagon")

  @type entry :: %{
          id: non_neg_integer(),
          query: String.t(),
          timestamp: DateTime.t(),
          execution_time_ms: non_neg_integer(),
          row_count: non_neg_integer(),
          connection: String.t()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add(String.t(), non_neg_integer(), non_neg_integer(), String.t()) :: :ok
  def add(query, execution_time_ms, row_count, connection) do
    GenServer.cast(__MODULE__, {:add, query, execution_time_ms, row_count, connection})
  end

  @spec list() :: [entry()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @spec search(String.t()) :: [entry()]
  def search(term) do
    GenServer.call(__MODULE__, {:search, term})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, @history_dir)
    File.mkdir_p!(dir)
    path = Path.join(dir, "history.dets") |> String.to_charlist()

    {:ok, @table_name} =
      :dets.open_file(@table_name, [
        {:file, path},
        {:type, :set},
        {:auto_save, 60_000}
      ])

    next_id = compute_next_id()
    {:ok, %{next_id: next_id}}
  end

  @impl true
  def handle_cast({:add, query, execution_time_ms, row_count, connection}, state) do
    entry = %{
      id: state.next_id,
      query: query,
      timestamp: DateTime.utc_now(),
      execution_time_ms: execution_time_ms,
      row_count: row_count,
      connection: connection
    }

    :dets.insert(@table_name, {state.next_id, entry})
    prune(state.next_id)
    {:noreply, %{state | next_id: state.next_id + 1}}
  end

  @impl true
  def handle_cast(:clear, _state) do
    :dets.delete_all_objects(@table_name)
    {:noreply, %{next_id: 0}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    entries =
      :dets.foldl(
        fn {_id, entry}, acc -> [entry | acc] end,
        [],
        @table_name
      )
      |> Enum.sort_by(& &1.id, :desc)

    {:reply, entries, state}
  end

  @impl true
  def handle_call({:search, term}, _from, state) do
    downcased = String.downcase(term)

    entries =
      :dets.foldl(
        fn {_id, entry}, acc ->
          if String.contains?(String.downcase(entry.query), downcased) do
            [entry | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )
      |> Enum.sort_by(& &1.id, :desc)

    {:reply, entries, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@table_name)
  end

  defp compute_next_id do
    :dets.foldl(
      fn {id, _entry}, max_id -> max(id, max_id) end,
      -1,
      @table_name
    ) + 1
  end

  defp prune(current_id) when current_id >= @max_entries do
    cutoff = current_id - @max_entries

    :dets.foldl(
      fn {id, _entry}, acc ->
        if id <= cutoff do
          :dets.delete(@table_name, id)
        end

        acc
      end,
      :ok,
      @table_name
    )
  end

  defp prune(_current_id), do: :ok
end
