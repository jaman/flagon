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
      conn_schemas: %{},
      conn_statuses: %{},
      query_target: nil,
      selected_node: nil,
      query_text: "",
      result: nil,
      result_page: 1,
      page_size: config.page_size,
      executing?: false,
      error: nil,
      query_task: nil
    }
  end

  def on_ready(state) do
    Flagon.Connection.Manager.load_connections(state.connections)

    statuses =
      Map.new(state.connections, fn c ->
        {to_string(c.name), :disconnected}
      end)

    state = %{state | conn_statuses: statuses}

    Enum.reduce(state.connections, state, fn conn_config, acc ->
      start_connect(conn_config, acc)
    end)
  end

  def render(state) do
    vertical([
      render_header(state),
      render_main(state),
      render_footer()
    ])
  end

  def keybindings do
    [
      {"F5", "Run"},
      {"Ctrl+E", "Export"},
      {"Ctrl+H", "History"},
      {"Ctrl+R", "Refresh"},
      {"Esc", "Cancel"},
      {"Ctrl+Q", "Quit"}
    ]
  end

  def handle_event({:key, :f5}, state), do: run_query(state)
  def handle_event({:key, :enter, [:ctrl]}, state), do: run_query(state)

  def handle_event({:key, :r, [:ctrl]}, state) do
    case state.query_target do
      nil -> {:noreply, state}
      name -> do_refresh_schema(name, state)
    end
  end

  def handle_event({:key, :escape}, %{executing?: true} = state) do
    if state.query_task, do: Task.shutdown(state.query_task, :brutal_kill)
    {:ok, %{state | executing?: false, query_task: nil}}
  end

  def handle_event({:key, :q, [:ctrl]}, _state), do: {:stop, :normal}

  def handle_event(_event, state), do: {:noreply, state}

  def handle_event(:run_query, _data, state), do: run_query(state)

  def handle_event(:schema_node_selected, %{selected: [id]}, state) do
    handle_node_select(id, state)
  end

  def handle_event(:schema_node_selected, _data, state), do: {:noreply, state}

  def handle_event(:next_page, _data, state) do
    {:ok, %{state | result_page: state.result_page + 1}}
  end

  def handle_event(:prev_page, _data, state) do
    {:ok, %{state | result_page: max(1, state.result_page - 1)}}
  end

  def handle_event(:refresh_schema, _data, state) do
    case state.query_target do
      nil -> {:noreply, state}
      name -> do_refresh_schema(name, state)
    end
  end

  def handle_event(:quick_select_top, _data, state) do
    case selected_table_info(state) do
      {conn_name, node} ->
        conn_type = connection_type_for(conn_name, state)
        query = Flagon.Schema.default_query_for(node, conn_type, 1000)
        state = %{state | query_text: query, query_target: conn_name}
        run_query(state)

      nil ->
        {:noreply, state}
    end
  end

  def handle_event(:quick_count, _data, state) do
    case selected_table_info(state) do
      {conn_name, %{metadata: meta}} ->
        query = build_count_query(conn_name, meta, state)
        state = %{state | query_text: query, query_target: conn_name}
        run_query(state)

      nil ->
        {:noreply, state}
    end
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  def on_message({:query_complete, {:ok, result}}, state) do
    if state.query_target do
      Flagon.Query.History.add(
        state.query_text,
        result.execution_time_ms,
        result.row_count,
        state.query_target
      )
    end

    %{state | result: result, executing?: false, result_page: 1, error: nil, query_task: nil}
  end

  def on_message({:query_complete, {:error, reason}}, state) do
    %{state | error: "Query error: #{inspect(reason)}", executing?: false, query_task: nil}
  end

  def on_message({:connected, name}, state) do
    statuses = Map.put(state.conn_statuses, name, :connected)
    target = state.query_target || name
    %{state | conn_statuses: statuses, query_target: target}
  end

  def on_message({:connect_failed, name, reason}, state) do
    statuses = Map.put(state.conn_statuses, name, :error)
    %{state | conn_statuses: statuses, error: "#{name}: #{inspect(reason)}"}
  end

  def on_message({:schema_loaded, name, {:ok, tree}}, state) do
    schemas = Map.put(state.conn_schemas, name, tree)
    %{state | conn_schemas: schemas}
  end

  def on_message({:schema_loaded, name, {:error, reason}}, state) do
    %{state | error: "Schema #{name}: #{inspect(reason)}"}
  end

  def on_message(_msg, state), do: state

  defp render_header(state) do
    target_label =
      case state.query_target do
        nil -> "No target"
        name -> "Target: #{name}"
      end

    status =
      cond do
        state.executing? -> " [running...]"
        state.error -> " [error]"
        true -> ""
      end

    header("Flagon  #{target_label}#{status}")
  end

  defp render_main(state) do
    split_pane(
      [
        render_left_panel(state),
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
      ratio: 0.24,
      id: :main_split,
      flex: 1
    )
  end

  defp render_left_panel(state) do
    split_pane(
      [
        render_connection_tree(state),
        render_connection_info(state)
      ],
      orientation: :vertical,
      ratio: 0.75,
      id: :left_split
    )
  end

  defp render_connection_tree(state) do
    tree_data = build_connection_tree(state)

    tree(
      id: :schema_tree,
      data: Flagon.Schema.to_tree_data(tree_data),
      selection_mode: :single,
      on_select: :schema_node_selected
    )
  end

  defp render_connection_info(state) do
    case find_selected_connection(state) do
      nil ->
        label("Select a connection", style: %{dim: true})

      {name, conn_config} ->
        status = Map.get(state.conn_statuses, name, :disconnected)

        vertical([
          label(name, style: %{bold: true}),
          label("Type: #{conn_config.type}"),
          label(connection_address(conn_config)),
          label("Status: #{status}"),
          if state.query_target == name do
            label("Active query target", style: %{fg: {100, 255, 100}})
          else
            label("")
          end
        ])
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
    quick_actions = render_quick_actions(state)

    horizontal(
      [
        button(
          if(state.executing?, do: "Running...", else: "Run (F5)"),
          on_click: :run_query,
          style: %{bold: true}
        ),
        button("Refresh", on_click: :refresh_schema)
      ] ++ quick_actions,
      gap: 1
    )
  end

  defp render_quick_actions(state) do
    case selected_table_info(state) do
      nil ->
        []

      {_conn_name, _table_node} ->
        [
          button("Select Top 1000", on_click: :quick_select_top),
          button("Count", on_click: :quick_count)
        ]
    end
  end

  defp selected_table_info(state) do
    case state.selected_node do
      {:table, _, _} = id ->
        conn_name = find_owning_connection(id, state)
        node = find_node_by_id(id, state)
        if conn_name && node, do: {conn_name, node}

      _ ->
        nil
    end
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

  defp render_footer do
    footer()
  end

  defp build_connection_tree(state) do
    Enum.map(state.connections, fn conn_config ->
      name = to_string(conn_config.name)
      status = Map.get(state.conn_statuses, name, :disconnected)
      children = Map.get(state.conn_schemas, name, [])

      Flagon.Schema.connection_node(name, conn_config.type, status, children)
    end)
  end

  defp handle_node_select({:conn, name}, state) do
    {:ok, %{state | query_target: name, selected_node: {:conn, name}}}
  end

  defp handle_node_select({:table, _ns_or_schema, _table} = id, state) do
    conn_name = find_owning_connection(id, state)

    case conn_name do
      nil ->
        {:ok, %{state | selected_node: id}}

      name ->
        conn_type = connection_type_for(name, state)
        node = find_node_by_id(id, state)
        query = Flagon.Schema.default_query_for(node, conn_type, state.page_size)

        {:ok, %{state | query_target: name, query_text: query, selected_node: id}}
    end
  end

  defp handle_node_select(id, state) do
    conn_name = find_owning_connection(id, state)

    if conn_name do
      {:ok, %{state | query_target: conn_name, selected_node: id}}
    else
      {:ok, %{state | selected_node: id}}
    end
  end

  defp find_owning_connection(node_id, state) do
    Enum.find_value(state.connections, fn conn_config ->
      name = to_string(conn_config.name)
      children = Map.get(state.conn_schemas, name, [])

      if node_in_tree?(node_id, children) do
        name
      end
    end)
  end

  defp node_in_tree?(target_id, nodes) do
    Enum.any?(nodes, fn node ->
      node.id == target_id ||
        (is_list(node.children) && node_in_tree?(target_id, node.children))
    end)
  end

  defp find_node_by_id(target_id, state) do
    Enum.find_value(state.conn_schemas, fn {_name, nodes} ->
      find_in_tree(target_id, nodes)
    end)
  end

  defp find_in_tree(target_id, nodes) do
    Enum.find_value(nodes, fn node ->
      cond do
        node.id == target_id -> node
        is_list(node.children) -> find_in_tree(target_id, node.children)
        true -> nil
      end
    end)
  end

  defp find_selected_connection(state) do
    name =
      case state.selected_node do
        {:conn, n} -> n
        _ -> state.query_target
      end

    case name do
      nil ->
        nil

      n ->
        config = Enum.find(state.connections, &(to_string(&1.name) == n))
        if config, do: {n, config}
    end
  end

  defp run_query(state) do
    query_text =
      case Drafter.get_widget_value(:query_editor) do
        nil -> state.query_text
        text -> String.trim(text)
      end

    cond do
      query_text == "" ->
        {:ok, %{state | error: "No query to execute"}}

      state.query_target == nil ->
        {:ok, %{state | error: "No connection selected"}}

      true ->
        caller = self()
        target = state.query_target

        task =
          Task.async(fn ->
            Flagon.Connection.Manager.switch(target)
            result = Flagon.Query.Executor.execute_sync(query_text, timeout: state.config.query_timeout_ms)
            send(caller, {:query_complete, result})
          end)

        {:ok, %{state | executing?: true, error: nil, query_text: query_text, query_task: task}}
    end
  end

  defp start_connect(conn_config, state) do
    name = to_string(conn_config.name)
    caller = self()
    statuses = Map.put(state.conn_statuses, name, :connecting)

    Task.start(fn ->
      case Flagon.Connection.Manager.connect(name) do
        {:ok, _conn} ->
          send(caller, {:connected, name})

          case Flagon.Connection.Manager.introspect_connection(name) do
            {:ok, tree} -> send(caller, {:schema_loaded, name, {:ok, tree}})
            error -> send(caller, {:schema_loaded, name, error})
          end

        {:error, reason} ->
          send(caller, {:connect_failed, name, reason})
      end
    end)

    %{state | conn_statuses: statuses}
  end

  defp do_refresh_schema(name, state) do
    caller = self()

    Task.start(fn ->
      case Flagon.Connection.Manager.refresh_schema_for(name) do
        {:ok, tree} -> send(caller, {:schema_loaded, name, {:ok, tree}})
        error -> send(caller, {:schema_loaded, name, error})
      end
    end)

    {:ok, state}
  end

  defp query_placeholder(state) do
    case connection_type_for(state.query_target, state) do
      :kdb -> "select from trade where date=.z.d"
      :postgres -> "SELECT * FROM users LIMIT 100"
      :duckdb -> "SELECT * FROM read_parquet('data.parquet')"
      _ -> "Enter query..."
    end
  end

  defp connection_type_for(nil, _state), do: nil

  defp connection_type_for(name, state) do
    case Enum.find(state.connections, &(to_string(&1.name) == name)) do
      %{type: type} -> type
      _ -> nil
    end
  end

  defp connection_address(%{dsn: dsn}) when is_binary(dsn), do: dsn
  defp connection_address(%{path: path}) when is_binary(path), do: path

  defp connection_address(config) do
    host = Map.get(config, :host, "localhost")
    port = Map.get(config, :port, "")
    "#{host}:#{port}"
  end

  defp build_count_query(conn_name, meta, state) do
    case connection_type_for(conn_name, state) do
      :kdb ->
        ns = Map.get(meta, :namespace, "")
        table = Map.get(meta, :table, "")
        qualified = qualified_kdb_name(ns, table)
        "count #{qualified}"

      _ ->
        schema = Map.get(meta, :schema, "public")
        table = Map.get(meta, :table, "")
        "SELECT COUNT(*) FROM #{schema}.#{table}"
    end
  end

  defp qualified_kdb_name(".", name), do: name
  defp qualified_kdb_name(".root", name), do: name
  defp qualified_kdb_name("", name), do: name
  defp qualified_kdb_name(ns, name), do: "#{ns}.#{name}"
end
