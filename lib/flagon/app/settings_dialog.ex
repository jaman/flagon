defmodule Flagon.App.SettingsDialog do
  use Drafter.Screen

  @doc """
  Theme choices for the settings list, derived from the themes Drafter actually
  supports so the configured default is always selectable.
  """
  @spec theme_options() :: [{String.t(), String.t()}]
  def theme_options do
    Drafter.Theme.available_themes()
    |> Map.keys()
    |> Enum.sort()
    |> Enum.map(fn name -> {name, name} end)
  end

  def mount(props) do
    %{
      page_size: props.page_size,
      query_timeout_ms: props.query_timeout_ms,
      theme: props.theme,
      page_size_str: to_string(props.page_size),
      timeout_str: to_string(props.query_timeout_ms)
    }
  end

  def render(state) do
    options = theme_options()
    theme_count = length(options) + 1

    vertical([
      label("Settings", style: %{bold: true}),
      label(""),
      horizontal(
        [label("Page Size:", width: 20), text_input(id: :page_size_input, value: state.page_size_str, on_change: :page_size_changed)],
        height: 1
      ),
      horizontal(
        [label("Query Timeout (ms):", width: 20), text_input(id: :timeout_input, value: state.timeout_str, on_change: :timeout_changed)],
        height: 1
      ),
      horizontal(
        [label("Theme:", width: 20), option_list(options, id: :theme_select, on_select: :theme_selected, height: theme_count)],
        height: theme_count
      ),
      label(""),
      horizontal(
        [
          button("Save", on_click: :save, compact: true),
          button("Cancel", on_click: :cancel, compact: true)
        ],
        gap: 1,
        height: 1
      )
    ])
  end

  def handle_event({:key, :escape}, _data, _state) do
    Drafter.send_app_event(:settings_result, :dismissed)
    {:pop, :dismissed}
  end

  def handle_event(:cancel, _data, _state) do
    Drafter.send_app_event(:settings_result, :dismissed)
    {:pop, :dismissed}
  end

  def handle_event(:save, _data, state) do
    with {:ok, page_size} <- parse_positive_integer(state.page_size_str, "Page Size"),
         {:ok, timeout} <- parse_positive_integer(state.timeout_str, "Query Timeout") do
      settings = %{page_size: page_size, query_timeout_ms: timeout, theme: state.theme}
      Drafter.send_app_event(:settings_result, {:saved, settings})
      {:pop, {:settings, settings}}
    else
      {:error, _reason} -> {:noreply, state}
    end
  end

  def handle_event(:page_size_changed, value, state) do
    {:ok, %{state | page_size_str: value}}
  end

  def handle_event(:timeout_changed, value, state) do
    {:ok, %{state | timeout_str: value}}
  end

  def handle_event(:theme_selected, %{id: theme_id}, state) do
    {:ok, %{state | theme: theme_id}}
  end

  def handle_event(:theme_selected, theme, state) when is_binary(theme) do
    {:ok, %{state | theme: theme}}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  defp parse_positive_integer(str, label) do
    case Integer.parse(String.trim(str)) do
      {value, ""} when value > 0 -> {:ok, value}
      _ -> {:error, "#{label} must be a positive integer"}
    end
  end
end
