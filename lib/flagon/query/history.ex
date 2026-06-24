defmodule Flagon.Query.History do
  @moduledoc """
  Persisted query history backed by a Cachex cache with on-disk snapshots.

  Entries are keyed by an incrementing id and capped at the most recent
  `#{100}`. The cache is snapshotted to `history.cachex` under the config dir
  after every mutation and restored on boot, so history survives restarts
  without DETS's repair-on-dirty-shutdown behaviour.
  """

  use GenServer

  @max_entries 100
  @cache :flagon_history

  @type entry :: %{
          id: non_neg_integer(),
          query: String.t(),
          timestamp: DateTime.t(),
          execution_time_ms: non_neg_integer(),
          row_count: non_neg_integer(),
          connection: String.t(),
          result: Flagon.Query.Result.t() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec add(String.t(), Flagon.Query.Result.t(), String.t()) :: :ok
  def add(query, result, connection) do
    GenServer.cast(__MODULE__, {:add, query, result, connection})
  end

  @spec list() :: [entry()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @spec get(non_neg_integer()) :: entry() | nil
  def get(id) do
    GenServer.call(__MODULE__, {:get, id})
  end

  @spec clear() :: :ok
  def clear do
    GenServer.cast(__MODULE__, :clear)
  end

  @impl true
  def init(_opts) do
    restore()
    {:ok, %{next_id: compute_next_id()}}
  end

  @impl true
  def handle_cast({:add, query, result, connection}, state) do
    entry = %{
      id: state.next_id,
      query: query,
      timestamp: DateTime.utc_now(),
      execution_time_ms: result.execution_time_ms,
      row_count: result.row_count,
      connection: connection,
      result: result
    }

    Cachex.put(@cache, state.next_id, entry)
    prune(state.next_id)
    persist()
    {:noreply, %{state | next_id: state.next_id + 1}}
  end

  @impl true
  def handle_cast(:clear, _state) do
    Cachex.clear(@cache)
    persist()
    {:noreply, %{next_id: 0}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, Enum.sort_by(all_entries(), & &1.id, :desc), state}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    {:reply, fetch(id), state}
  end

  defp fetch(id) do
    case Cachex.get(@cache, id) do
      {:ok, nil} -> nil
      {:ok, entry} -> entry
      _ -> nil
    end
  end

  defp all_entries do
    case Cachex.keys(@cache) do
      {:ok, keys} -> keys |> Enum.map(&fetch/1) |> Enum.reject(&is_nil/1)
      _ -> []
    end
  end

  defp compute_next_id do
    case Cachex.keys(@cache) do
      {:ok, [_ | _] = keys} -> Enum.max(keys) + 1
      _ -> 0
    end
  end

  defp prune(current_id) when current_id >= @max_entries do
    cutoff = current_id - @max_entries

    case Cachex.keys(@cache) do
      {:ok, keys} -> Enum.each(keys, fn id -> if id <= cutoff, do: Cachex.del(@cache, id) end)
      _ -> :ok
    end
  end

  defp prune(_current_id), do: :ok

  defp persist do
    path = persist_path()
    File.mkdir_p!(Path.dirname(path))
    Cachex.save(@cache, path)
  end

  defp restore do
    path = persist_path()
    if File.exists?(path), do: Cachex.restore(@cache, path)
  end

  defp persist_path do
    Path.join(Flagon.Config.config_dir(), "history.cachex")
  end
end
