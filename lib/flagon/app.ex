defmodule Flagon.App do
  @moduledoc """
  Main TUI application for Flagon.
  """

  use Drafter.App

  def mount(_props) do
    config = Process.get(:flagon_config, Flagon.Config.load())

    %{
      config: config,
      connections: config.connections,
      active_connection: nil,
      connection_status: %{},
      schema_tree: [],
      schema_loading?: false,
      query_text: "",
      result: nil,
      result_page: 1,
      page_size: config.page_size,
      executing?: false,
      active_tab: :table,
      error: nil,
      query_task: nil
    }
  end

  def on_ready(state) do
    Flagon.Connection.Manager.load_connections(state.connections)

    case state.connections do
      [first | _] -> auto_connect(first, state)
      [] -> state
    end
  end

  def render(state) do
    vertical([
      render_header(state),
      render_main(state),
      render_footer(state)
    ])
  end

  def keybindings do
    [
      {"F5", "Run"},
      {"Ctrl+E", "Export"},
      {"Ctrl+H", "History"},
      {"Esc", "Cancel"},
      {"q", "Quit"}
    ]
  end

  def handle_event({:key, :f5}, state), do: run_query(state)
  def handle_event({:key, :enter, [:ctrl]}, state), do: run_query(state)

  def handle_event({:key, :escape}, %{executing?: true} = state) do
    if state.query_task, do: Task.shutdown(state.query_task, :brutal_kill)
    {:ok, %{state | executing?: false, query_task: nil}}
  end

  def handle_event({:key, :q}, state) do
    if state.executing? do
      {:noreply, state}
    else
      {:stop, :normal}
    end
  end

  def handle_event(_event, state), do: {:noreply, state}

  def handle_event(:run_query, _data, state), do: run_query(state)

  def handle_event(:connection_selected, %{selected: name}, state) do
    case Flagon.Connection.Manager.connect(name) do
      {:ok, _conn} ->
        Flagon.Connection.Manager.switch(name)
        {:ok, %{state | active_connection: name, schema_tree: [], error: nil}}

      {:error, reason} ->
        {:ok, %{state | error: "Connection failed: #{inspect(reason)}"}}
    end
  end

  def handle_event(:schema_node_selected, %{selected: [{:table, ns, table_name}]}, state) do
    query =
      case connection_type(state) do
        :kdb -> "select from #{qualified_name(ns, table_name)}"
        _ -> "SELECT * FROM #{table_name} LIMIT #{state.page_size}"
      end

    {:ok, %{state | query_text: query}}
  end

  def handle_event(:schema_node_selected, _data, state), do: {:noreply, state}

  def handle_event(:tab_changed, %{tab: tab}, state) do
    {:ok, %{state | active_tab: tab}}
  end

  def handle_event(:next_page, _data, state) do
    {:ok, %{state | result_page: state.result_page + 1}}
  end

  def handle_event(:prev_page, _data, state) do
    {:ok, %{state | result_page: max(1, state.result_page - 1)}}
  end

  def handle_event(:refresh_schema, _data, state) do
    do_refresh_schema(state)
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  def on_message({:query_complete, {:ok, result}}, state) do
    if state.active_connection do
      Flagon.Query.History.add(
        state.query_text,
        result.execution_time_ms,
        result.row_count,
        state.active_connection
      )
    end

    %{state | result: result, executing?: false, result_page: 1, error: nil, query_task: nil}
  end

  def on_message({:query_complete, {:error, reason}}, state) do
    %{state | error: "Query error: #{inspect(reason)}", executing?: false, query_task: nil}
  end

  def on_message({:schema_loaded, {:ok, tree}}, state) do
    %{state | schema_tree: tree, schema_loading?: false}
  end

  def on_message({:schema_loaded, {:error, reason}}, state) do
    %{state | error: "Schema error: #{inspect(reason)}", schema_loading?: false}
  end

  def on_message(_msg, state), do: state

  defp render_header(state) do
    conn_label =
      case state.active_connection do
        nil -> "No Connection"
        name -> name
      end

    status =
      cond do
        state.executing? -> " [running...]"
        state.error -> " [error]"
        true -> ""
      end

    header("Flagon  #{conn_label}#{status}")
  end

  defp render_main(state) do
    split_pane(
      [
        render_schema_panel(state),
        split_pane(
          [
            render_query_panel(state),
            render_results_panel(state)
          ],
          orientation: :vertical,
          ratio: 0.35,
          id: :query_results_split
        )
      ],
      orientation: :horizontal,
      ratio: 0.22,
      id: :main_split,
      flex: 1
    )
  end

  defp render_schema_panel(state) do
    if state.schema_loading? do
      vertical([
        label("Schema"),
        loading_indicator(style: :dots)
      ])
    else
      tree(
        id: :schema_tree,
        data: Flagon.Schema.to_tree_data(state.schema_tree),
        selection_mode: :single,
        on_select: :schema_node_selected
      )
    end
  end

  defp render_query_panel(state) do
    vertical([
      text_area(
        id: :query_editor,
        text: state.query_text,
        placeholder: query_placeholder(state),
        show_line_numbers: true,
        flex: 1
      ),
      render_toolbar(state)
    ])
  end

  defp render_toolbar(state) do
    horizontal(
      [
        button(if(state.executing?, do: "Running...", else: "Run (F5)"),
          on_click: :run_query,
          style: %{bold: true}
        ),
        button("Refresh Schema", on_click: :refresh_schema)
      ],
      gap: 1
    )
  end

  defp render_results_panel(state) do
    cond do
      state.error ->
        vertical([
          label("Error", style: %{bold: true, fg: {255, 80, 80}}),
          label(state.error)
        ])

      state.result == nil ->
        label("No results. Press F5 to run a query.", style: %{dim: true})

      true ->
        render_result_tabs(state)
    end
  end

  defp render_result_tabs(state) do
    result = state.result
    {dt_columns, dt_data, total_pages} =
      Flagon.Query.Result.to_data_table_format(result, state.result_page, state.page_size)

    table_tab =
      vertical([
        data_table(
          id: :results_table,
          columns: dt_columns,
          data: dt_data,
          zebra_stripes: true,
          flex: 1
        ),
        render_pagination(state.result_page, total_pages, result.row_count, result.execution_time_ms)
      ])

    raw_tab =
      scrollable(
        [pretty(result.rows, id: :raw_results)],
        flex: 1
      )

    tabbed_content([
      {"Table (#{result.row_count} rows)", table_tab},
      {"Raw", raw_tab}
    ])
  end

  defp render_pagination(page, total_pages, row_count, elapsed_ms) do
    info = "Page #{page}/#{total_pages}  |  #{row_count} rows  |  #{elapsed_ms}ms"

    horizontal(
      [
        button("< Prev", on_click: :prev_page),
        label(info, style: %{dim: true}),
        button("Next >", on_click: :next_page)
      ],
      gap: 1
    )
  end

  defp render_footer(_state) do
    footer()
  end

  defp run_query(state) do
    query_text =
      case Drafter.get_widget_value(:query_editor) do
        nil -> state.query_text
        text -> String.trim(text)
      end

    if query_text == "" do
      {:ok, %{state | error: "No query to execute"}}
    else
      caller = self()

      task =
        Task.async(fn ->
          result = Flagon.Query.Executor.execute_sync(query_text, timeout: state.config.query_timeout_ms)
          send(caller, {:query_complete, result})
        end)

      {:ok, %{state | executing?: true, error: nil, query_text: query_text, query_task: task}}
    end
  end

  defp auto_connect(conn_config, state) do
    name = to_string(conn_config.name)
    caller = self()

    Task.start(fn ->
      case Flagon.Connection.Manager.connect(name) do
        {:ok, _conn} ->
          case Flagon.Connection.Manager.introspect() do
            {:ok, tree} -> send(caller, {:schema_loaded, {:ok, tree}})
            error -> send(caller, {:schema_loaded, error})
          end

        {:error, reason} ->
          send(caller, {:schema_loaded, {:error, reason}})
      end
    end)

    %{state | active_connection: name, schema_loading?: true}
  end

  defp do_refresh_schema(state) do
    caller = self()

    Task.start(fn ->
      case Flagon.Connection.Manager.refresh_schema() do
        {:ok, tree} -> send(caller, {:schema_loaded, {:ok, tree}})
        error -> send(caller, {:schema_loaded, error})
      end
    end)

    {:ok, %{state | schema_loading?: true}}
  end

  defp query_placeholder(state) do
    case connection_type(state) do
      :kdb -> "select from trade where date=.z.d"
      :postgres -> "SELECT * FROM users LIMIT 100"
      :duckdb -> "SELECT * FROM read_parquet('data.parquet')"
      _ -> "Enter query..."
    end
  end

  defp connection_type(state) do
    case Enum.find(state.connections, &(to_string(&1.name) == state.active_connection)) do
      %{type: type} -> type
      _ -> nil
    end
  end

  defp qualified_name(".", name), do: name
  defp qualified_name(".root", name), do: name
  defp qualified_name(ns, name), do: "#{ns}.#{name}"
end
