defmodule Flagon.Query.History do
  @moduledoc """
  Persisted query history ring buffer.
  """

  use GenServer

  @max_entries 500
  @history_file Path.expand("~/.config/flagon/history.dat")

  defstruct entries: [], max: @max_entries

  @type entry :: %{
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
  def init(_opts) do
    entries = load_from_disk()
    {:ok, %__MODULE__{entries: entries}}
  end

  @impl true
  def handle_cast({:add, query, execution_time_ms, row_count, connection}, state) do
    entry = %{
      query: query,
      timestamp: DateTime.utc_now(),
      execution_time_ms: execution_time_ms,
      row_count: row_count,
      connection: connection
    }

    entries = [entry | state.entries] |> Enum.take(state.max)
    persist(entries)
    {:noreply, %{state | entries: entries}}
  end

  @impl true
  def handle_cast(:clear, state) do
    persist([])
    {:noreply, %{state | entries: []}}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, state.entries, state}
  end

  @impl true
  def handle_call({:search, term}, _from, state) do
    downcased = String.downcase(term)

    results =
      Enum.filter(state.entries, fn entry ->
        String.contains?(String.downcase(entry.query), downcased)
      end)

    {:reply, results, state}
  end

  defp load_from_disk do
    case File.read(@history_file) do
      {:ok, binary} ->
        try do
          :erlang.binary_to_term(binary)
        rescue
          _ -> []
        end

      {:error, _} ->
        []
    end
  end

  defp persist(entries) do
    dir = Path.dirname(@history_file)
    File.mkdir_p!(dir)
    File.write!(@history_file, :erlang.term_to_binary(entries))
  end
end
