defmodule Flagon.App.HistoryDialog do
  use Drafter.Screen

  def mount(_props) do
    entries = Flagon.Query.History.list()

    %{
      entries: entries,
      selected: 0
    }
  end

  def render(state) do
    items =
      state.entries
      |> Enum.with_index()
      |> Enum.map(fn {entry, idx} ->
        label = format_label(entry)
        {label, idx}
      end)

    vertical([
      label("Select a query to load into the editor", style: %{dim: true}),
      option_list(
        items,
        id: :history_list,
        on_select: :history_selected,
        height: :auto
      ),
      horizontal(
        [
          button("Load", on_click: :load_query, compact: true),
          button("Clear All", on_click: :clear_history, compact: true),
          button("Close", on_click: :close, compact: true)
        ],
        gap: 1,
        height: 1
      )
    ])
  end

  def handle_event({:key, :escape}, _data, _state) do
    {:pop, :dismissed}
  end

  def handle_event({:key, :enter}, _data, state) do
    load_selected(state)
  end

  def handle_event(:close, _data, _state) do
    {:pop, :dismissed}
  end

  def handle_event(:load_query, _data, state) do
    load_selected(state)
  end

  def handle_event(:history_selected, %{id: idx}, state) when is_integer(idx) do
    {:ok, %{state | selected: idx}}
  end

  def handle_event(:history_selected, idx, state) when is_integer(idx) do
    {:ok, %{state | selected: idx}}
  end

  def handle_event(:clear_history, _data, state) do
    Flagon.Query.History.clear()
    {:ok, %{state | entries: [], selected: 0}}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  defp load_selected(state) do
    case Enum.at(state.entries, state.selected) do
      nil ->
        {:pop, :dismissed}

      entry ->
        Drafter.send_app_event(:history_result, {:use_query, entry.query})
        {:pop, :used}
    end
  end

  defp format_label(entry) do
    conn = String.pad_trailing(entry.connection, 12)
    query = entry.query |> String.replace("\n", " ") |> String.slice(0, 60)
    time = "#{entry.execution_time_ms}ms"
    rows = "#{entry.row_count} rows"
    "#{conn} #{query}  (#{rows}, #{time})"
  end
end
