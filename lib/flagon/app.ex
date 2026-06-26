defmodule Flagon.App do
  @moduledoc """
  Main TUI application for Flagon.
  """

  use Drafter.App

  @editor_table :flagon_editor_state

  @key_hints [
    {"F4", "Connections"},
    {"F5", "Run All"},
    {"F6", "Run Line"},
    {"F7", "Run Selection"},
    {"F8", "History"},
    {"F9", "Settings"},
    {"Ctrl+R", "Refresh"},
    {"Ctrl+S", "Export"},
    {"Ctrl+Y", "Copy"},
    {"Ctrl+Q", "Quit"}
  ]

  def mount(_props) do
    config = Application.get_env(:flagon, :loaded_config) || Flagon.Config.load()

    first_name =
      case config.connections do
        [first | _] -> Flagon.Config.qualified_name(first)
        [] -> nil
      end

    init_editor_table()

    %{
      config: config,
      connections: config.connections,
      conn_schemas: %{},
      conn_statuses: %{},
      query_target: first_name,
      query_text: load_editor(first_name),
      result: nil,
      result_page: 1,
      result_tab: :result,
      chart_type: "line",
      page_size: config.page_size,
      executing?: false,
      error: nil,
      query_task: nil,
      history_selected: 0,
      preview: nil,
      executed_query: nil
    }
  end

  def on_ready(state) do
    Flagon.Connection.Manager.load_connections(state.connections)

    statuses =
      Map.new(state.connections, fn c ->
        {Flagon.Config.qualified_name(c), :disconnected}
      end)

    %{state | conn_statuses: statuses}
  end

  def render(state) do
    vertical([
      render_header(state),
      render_main(state),
      footer(bindings: @key_hints)
    ])
  end

  keybinding :f5, "Run All" do
    run_query(state)
  end

  keybinding :f6, "Run Line" do
    run_extracted(:line, state)
  end

  keybinding {:enter, [:ctrl]}, "Run Line" do
    run_extracted(:line, state)
  end

  keybinding :f7, "Run Selection" do
    run_extracted(:selection, state)
  end

  keybinding :f4, "Connections" do
    {:show_modal, Flagon.App.ConnectionDialog, %{connections: state.connections},
     [title: "Connections", width: 60, height: 20]}
  end

  keybinding :f8, "History" do
    {:show_modal, Flagon.App.HistoryDialog, %{}, [title: "Query History", width: 70, height: 20]}
  end

  keybinding :f9, "Settings" do
    props = %{
      page_size: state.page_size,
      query_timeout_ms: state.config.query_timeout_ms,
      theme: state.config.theme
    }

    {:show_modal, Flagon.App.SettingsDialog, props, [title: "Settings", width: 50, height: 18]}
  end

  keybinding {:r, [:ctrl]}, "Refresh" do
    case state.query_target do
      nil -> {:noreply, state}
      name -> do_refresh_schema(name, state)
    end
  end

  keybinding {:s, [:ctrl]}, "Export CSV" do
    case state.result do
      nil -> {:noreply, state}
      result -> export_csv(result, state)
    end
  end

  keybinding {:y, [:ctrl]}, "Copy" do
    case state.result do
      nil -> {:noreply, state}
      result ->
        case Flagon.Export.Clipboard.copy(result) do
          :ok -> {:ok, %{state | error: nil}}
          {:error, reason} -> {:ok, %{state | error: "Copy failed: #{inspect(reason)}"}}
        end
    end
  end

  keybinding {:q, [:ctrl]}, "Quit" do
    {:stop, :normal}
  end

  def handle_event({:key, :escape}, %{executing?: true} = state) do
    if state.query_task, do: Task.shutdown(state.query_task, :brutal_kill)
    {:ok, %{state | executing?: false, query_task: nil}}
  end

  def handle_event(_event, state), do: {:noreply, state}

  def handle_event(:connection_selected, [%{id: {:server, id}} | _], state) do
    switch_connection(id, state)
  end

  def handle_event(:connection_selected, [%{id: {:folder, _path}} | _], state) do
    {:noreply, state}
  end

  def handle_event(:run_query, _data, state), do: run_query(state)

  def handle_event(:run_line, _data, state), do: run_extracted(:line, state)

  def handle_event(:run_selection, _data, state), do: run_extracted(:selection, state)

  def handle_event(:run_text, text, state), do: run_query(state, text)

  def handle_event(:schema_node_selected, [%{id: {:table, _, _}, metadata: meta} | _], state) do
    conn_type = connection_type_for(state.query_target, state)
    node = %{type: :table, metadata: meta}
    query = Flagon.Schema.default_query_for(node, conn_type, state.page_size)
    run_query(%{state | query_text: query})
  end

  def handle_event(:schema_node_selected, [%{id: {:func, _, _}, metadata: meta} | _], state) do
    name = Map.get(meta, :function, "?")
    params = Map.get(meta, :params, [])
    body = Map.get(meta, :body, "")

    preview = %{
      type: :function,
      name: name,
      signature: "#{name}[#{Enum.join(params, ";")}]",
      params: params,
      body: body
    }

    {:ok, %{state | preview: preview, result_tab: :result, error: nil}}
  end

  def handle_event(:schema_node_selected, [%{id: {:var, _, _}, metadata: meta} | _], state) do
    name = Map.get(meta, :variable, "?")
    namespace = Map.get(meta, :namespace, ".")

    preview = %{
      type: :variable,
      name: name,
      namespace: namespace
    }

    {:ok, %{state | preview: preview, result_tab: :result, error: nil}}
  end

  def handle_event(:schema_node_selected, _data, state), do: {:noreply, state}

  def handle_event(:schema_node_expanded, {%{id: {:table, namespace, table}}, true}, state) do
    load_columns_async(state.query_target, namespace, table)
    {:noreply, state}
  end

  def handle_event(:schema_node_expanded, _data, state), do: {:noreply, state}

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

  def handle_event(:tab_result, _data, state), do: {:ok, %{state | result_tab: :result}}
  def handle_event(:tab_chart, _data, state), do: {:ok, %{state | result_tab: :chart}}
  def handle_event(:tab_history, _data, state), do: {:ok, %{state | result_tab: :history}}

  def handle_event(:chart_type_selected, %{id: type}, state), do: {:ok, %{state | chart_type: type}}
  def handle_event(:chart_type_selected, type, state) when is_binary(type), do: {:ok, %{state | chart_type: type}}

  def handle_event(:history_select, %{id: idx}, state) when is_integer(idx) do
    {:ok, %{state | history_selected: idx}}
  end

  def handle_event(:history_select, idx, state) when is_integer(idx) do
    {:ok, %{state | history_selected: idx}}
  end

  def handle_event(:history_load, _data, state) do
    load_history_entry(state.history_selected, state)
  end

  def handle_event(:clear_history, _data, state) do
    Flagon.Query.History.clear()
    {:ok, state}
  end

  def handle_event(:history_result, {:use_query, query}, state) do
    {:ok, %{state | query_text: query, result_tab: :result}}
  end

  def handle_event(:show_connections, _data, state) do
    {:show_modal, Flagon.App.ConnectionDialog, %{connections: state.connections},
     [title: "Connections", width: 60, height: 20]}
  end

  def handle_event(:connection_result, {:updated, connections}, state) do
    config = %{state.config | connections: connections}
    Flagon.Config.save(config)
    Flagon.Connection.Manager.load_connections(connections)
    {:ok, reconcile_connections(state, config, connections)}
  end

  def handle_event(:connection_result, _data, state), do: {:noreply, state}

  def handle_event(:settings_result, {:saved, settings}, state) do
    config = %{state.config | page_size: settings.page_size, query_timeout_ms: settings.query_timeout_ms, theme: settings.theme}
    Flagon.Config.save(config)
    {:ok, %{state | config: config, page_size: settings.page_size}}
  end

  def handle_event(:settings_result, _data, state), do: {:noreply, state}

  def handle_event(_event, _data, state), do: {:noreply, state}

  def on_message({:query_complete, {:ok, result}}, state) do
    if state.query_target do
      Flagon.Query.History.add(state.executed_query || state.query_text, result, state.query_target)
    end

    %{state | result: result, executing?: false, result_page: 1, result_tab: :result, error: nil, query_task: nil}
  end

  def on_message({:query_complete, {:error, reason}}, state) do
    %{state | error: "Query error: #{inspect(reason)}", executing?: false, query_task: nil}
  end

  def on_message({:connected, name}, state) do
    statuses = Map.put(state.conn_statuses, name, :connected)
    %{state | conn_statuses: statuses}
  end

  def on_message({:connect_failed, name, reason}, state) do
    statuses = Map.put(state.conn_statuses, name, :error)
    %{state | conn_statuses: statuses, executing?: false, query_task: nil, error: "#{name}: #{inspect(reason)}"}
  end

  def on_message({:query_reconnecting, name}, state) do
    statuses = Map.put(state.conn_statuses, name, :connecting)
    %{state | conn_statuses: statuses}
  end

  def on_message({:schema_loaded, name, {:ok, tree}}, state) do
    schemas = Map.put(state.conn_schemas, name, tree)
    %{state | conn_schemas: schemas}
  end

  def on_message({:schema_loaded, name, {:error, reason}}, state) do
    %{state | error: "Schema #{name}: #{inspect(reason)}"}
  end

  def on_message({:columns_loaded, target, node_id, columns}, state) do
    case Map.get(state.conn_schemas, target) do
      nil ->
        state

      schema ->
        updated = Flagon.Schema.put_node_children(schema, node_id, columns)
        %{state | conn_schemas: Map.put(state.conn_schemas, target, updated)}
    end
  end

  def on_message(_msg, state), do: state

  defp render_header(state) do
    conn_label =
      case state.query_target do
        nil -> "No connection"
        name ->
          status = Map.get(state.conn_statuses, name, :disconnected)
          type_label = connection_type_label(state.query_target, state)
          "#{name} (#{type_label}) [#{status}]"
      end

    status =
      cond do
        state.executing? -> " | running..."
        state.error -> " | error"
        true -> ""
      end

    header("Flagon  Server: #{conn_label}#{status}")
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
          id: :query_results_split,
          resize_mode: :live
        )
      ],
      orientation: :horizontal,
      ratio: 0.24,
      id: :main_split,
      flex: 1,
      resize_mode: :live
    )
  end

  defp render_left_panel(state) do
    split_pane(
      [
        vertical([
          label("Servers", style: %{bold: true}),
          tree(
            id: :conn_tree,
            data: Flagon.App.ConnectionTree.build(state.connections, state.conn_statuses),
            selection_mode: :single,
            on_select: :connection_selected,
            flex: 1
          )
        ]),
        render_schema_tree(state)
      ],
      orientation: :vertical,
      ratio: 0.3,
      id: :left_split,
      resize_mode: :live
    )
  end

  defp render_schema_tree(state) do
    schema_data =
      case state.query_target do
        nil -> []
        name -> Map.get(state.conn_schemas, name, [])
      end

    if schema_data == [] do
      status = Map.get(state.conn_statuses, state.query_target, :disconnected)

      case status do
        :connecting -> label("Connecting...", style: %{dim: true})
        :error -> label("Connection failed", style: %{fg: {255, 80, 80}})
        _ -> label("No schema loaded", style: %{dim: true})
      end
    else
      tree(
        id: :schema_tree,
        data: Flagon.Schema.to_tree_data(schema_data),
        selection_mode: :single,
        on_select: :schema_node_selected,
        on_expand: :schema_node_expanded,
        flex: 1
      )
    end
  end

  defp render_query_panel(state) do
    vertical(
      [
        text_area(
          id: :query_editor,
          bind: :query_text,
          placeholder: query_placeholder(state),
          show_line_numbers: true,
          language: editor_language(state),
          trap_focus: :arrows,
          height: :auto
        ),
        render_toolbar(state)
      ],
      flex: 1
    )
  end

  defp render_toolbar(state) do
    horizontal(
      [
        button(
          if(state.executing?, do: "Running...", else: "Run All"),
          on_click: :run_query,
          compact: true,
          style: %{bold: true}
        ),
        button("Run Line", on_click: :run_line, compact: true),
        button("Run Sel", on_click: :run_selection, compact: true),
        button("Refresh", on_click: :refresh_schema, compact: true)
      ],
      gap: 1,
      height: 1
    )
  end

  defp render_results_panel(state) do
    vertical(
      [
        box(
          [render_result_content(state)],
          flex: 1
        ),
        render_result_tab_bar(state)
      ],
      flex: 1
    )
  end

  defp render_result_content(state) do
    cond do
      state.error ->
        vertical([
          label("Error", style: %{bold: true, fg: {255, 80, 80}}),
          label(state.error)
        ])

      state.result_tab == :history ->
        render_history_view(state)

      state.result_tab == :chart and state.result != nil ->
        render_chart_view(state)

      state.preview != nil and state.result_tab == :result ->
        render_preview(state.preview)

      state.result != nil ->
        render_result_table(state)

      true ->
        label("No results. Press F5 to run a query.", style: %{dim: true})
    end
  end

  @tab_active %{bold: true, fg: {255, 255, 255}, bg: {60, 60, 120}}
  @tab_inactive %{dim: true}

  defp render_result_tab_bar(state) do
    horizontal(
      [
        button("📋 Result", on_click: :tab_result, compact: true,
          style: if(state.result_tab == :result, do: @tab_active, else: @tab_inactive)),
        button("📊 Chart", on_click: :tab_chart, compact: true,
          style: if(state.result_tab == :chart, do: @tab_active, else: @tab_inactive)),
        button("🕓 History", on_click: :tab_history, compact: true,
          style: if(state.result_tab == :history, do: @tab_active, else: @tab_inactive))
      ],
      gap: 0,
      height: 1
    )
  end

  defp render_result_table(state) do
    result = state.result

    {dt_columns, dt_data, total_pages} =
      Flagon.Query.Result.to_data_table_format(result, state.result_page, state.page_size)

    vertical(
      [
        render_pagination(state.result_page, total_pages, result.row_count, result.execution_time_ms),
        data_table(
          id: :results_table,
          columns: dt_columns,
          data: dt_data,
          height: :auto,
          zebra_stripes: true,
          show_header: true,
          show_scrollbars: true,
          column_fit_mode: :expand,
          cursor_type: :cell
        )
      ],
      flex: 1
    )
  end

  @preview_label_style %{fg: {180, 180, 180}, dim: true}
  @preview_value_style %{fg: {255, 255, 255}}

  defp render_preview(%{type: :function} = preview) do
    vertical(
      [
        label("Function: #{preview.signature}", style: %{bold: true, fg: {255, 255, 255}}),
        label(""),
        horizontal([
          label("Parameters: ", width: 13, style: @preview_label_style),
          label(Enum.join(preview.params, ", "), flex: 1, style: @preview_value_style)
        ]),
        label(""),
        label("Definition:", style: @preview_label_style),
        code_view(preview.body, language: :q, show_line_numbers: true, flex: 1)
      ],
      flex: 1
    )
  end

  defp render_preview(%{type: :variable} = preview) do
    qualified =
      case preview.namespace do
        "." -> preview.name
        ns -> "#{ns}.#{preview.name}"
      end

    vertical([
      label("Variable: #{qualified}", style: %{bold: true, fg: {255, 255, 255}})
    ])
  end

  @chart_types [
    {"line", "line"},
    {"area", "area"},
    {"bar", "bar"},
    {"stacked_bar", "stacked_bar"},
    {"scatter", "scatter"},
    {"candlestick", "candlestick"},
    {"histogram", "histogram"},
    {"step", "step"},
    {"bubble", "bubble"},
    {"heatmap", "heatmap"}
  ]

  defp render_chart_view(state) do
    if Flagon.App.ChartView.chartable?(state.result) do
      chart_type_atom = String.to_existing_atom(state.chart_type)
      {chart_data, chart_opts} = Flagon.App.ChartView.auto_chart_data(state.result, chart_type_atom)

      split_pane(
        [
          render_chart_controls(state),
          vertical(
            [
              label(
                "#{state.result.row_count} rows  #{state.result.execution_time_ms}ms",
                style: %{dim: true},
                height: 1
              ),
              chart(chart_data, chart_opts)
            ],
            flex: 1
          )
        ],
        orientation: :horizontal,
        ratio: 0.2,
        id: :chart_split
      )
    else
      label("No numeric columns to chart.", style: %{dim: true})
    end
  end

  defp render_chart_controls(_state) do
    vertical([
      label("Type:", style: %{bold: true}, height: 1),
      option_list(
        @chart_types,
        id: :chart_type_select,
        on_select: :chart_type_selected,
        height: :auto
      )
    ])
  end

  defp render_history_view(state) do
    entries = Flagon.Query.History.list()

    if entries == [] do
      label("No query history yet.", style: %{dim: true})
    else
      items =
        entries
        |> Enum.with_index()
        |> Enum.map(fn {entry, idx} ->
          query = entry.query |> String.replace(~r/\s+/, " ") |> String.trim()
          {"#{query}", idx}
        end)

      selected_entry = Enum.at(entries, state.history_selected)

      split_pane(
        [
          vertical([
            label("Query", style: %{bold: true}, height: 1),
            option_list(
              items,
              id: :history_list,
              on_select: :history_select,
              height: :auto
            ),
            button("Clear", on_click: :clear_history, compact: true, height: 1)
          ]),
          render_history_result(selected_entry)
        ],
        orientation: :horizontal,
        ratio: 0.3,
        id: :history_split
      )
    end
  end

  defp render_history_result(nil), do: label("Select a query", style: %{dim: true})

  defp render_history_result(%{result: nil}), do: label("No result data", style: %{dim: true})

  defp render_history_result(entry) do
    result = entry.result

    {dt_columns, dt_data, _total_pages} =
      Flagon.Query.Result.to_data_table_format(result, 1, 1000)

    info = "#{entry.connection}  #{result.row_count} rows  #{result.execution_time_ms}ms"

    vertical(
      [
        label(info, style: %{dim: true}, height: 1),
        data_table(
          id: :history_results_table,
          columns: dt_columns,
          data: dt_data,
          height: :auto,
          zebra_stripes: true,
          show_header: true,
          show_scrollbars: true,
          column_fit_mode: :expand,
          cursor_type: :cell
        )
      ],
      flex: 1
    )
  end

  defp render_pagination(page, total_pages, row_count, elapsed_ms) do
    info = "Page #{page}/#{total_pages}  |  #{row_count} rows  |  #{elapsed_ms}ms"

    horizontal(
      [
        button("< Prev", on_click: :prev_page, compact: true),
        label(info, style: %{dim: true}),
        button("Next >", on_click: :next_page, compact: true)
      ],
      gap: 1,
      height: 1
    )
  end

  defp load_history_entry(idx, state) do
    entries = Flagon.Query.History.list()

    case Enum.at(entries, idx) do
      nil -> {:noreply, state}
      entry -> {:ok, %{state | query_text: entry.query, result_tab: :result}}
    end
  end

  defp switch_connection(name, state) do
    save_editor(state.query_target, state.query_text)

    caller = self()
    status = Map.get(state.conn_statuses, name, :disconnected)
    restored_text = load_editor(name)

    state = %{state | query_target: name, error: nil, query_text: restored_text}

    if status == :connected do
      Flagon.Connection.Manager.switch(name)
      {:ok, state}
    else
      attempt_connect(name, caller, state)
    end
  end

  defp attempt_connect(name, caller, state) do
    Task.start(fn ->
      Flagon.Connection.Manager.disconnect(name)

      case Flagon.Connection.Manager.connect(name) do
        {:ok, _} ->
          send(caller, {:connected, name})
          Flagon.Connection.Manager.switch(name)

          case Flagon.Connection.Manager.introspect_connection(name) do
            {:ok, tree} -> send(caller, {:schema_loaded, name, {:ok, tree}})
            error -> send(caller, {:schema_loaded, name, error})
          end

        {:error, reason} ->
          send(caller, {:connect_failed, name, reason})
      end
    end)

    statuses = Map.put(state.conn_statuses, name, :connecting)
    {:ok, %{state | conn_statuses: statuses}}
  end

  defp run_query(state, override \\ nil) do
    query_text = String.trim(override || state.query_text || "")
    state = %{state | preview: nil}

    cond do
      query_text == "" ->
        {:ok, %{state | error: "No query to execute"}}

      state.query_target == nil ->
        {:ok, %{state | error: "No connection selected"}}

      true ->
        caller = self()
        target = state.query_target
        timeout = state.config.query_timeout_ms

        task =
          Task.async(fn ->
            Flagon.Connection.Manager.switch(target)
            result = safe_execute(query_text, timeout)

            case result do
              {:ok, _} ->
                send(caller, {:query_complete, result})

              {:error, :timeout} ->
                send(caller, {:query_complete, {:error, :timeout}})

              {:error, _reason} ->
                reconnect_and_retry(caller, target, query_text, timeout)
            end
          end)

        {:ok,
         %{
           state
           | executing?: true,
             error: nil,
             result: nil,
             result_tab: :result,
             query_task: task,
             executed_query: query_text
         }}
    end
  end

  defp run_extracted(mode, state) do
    Task.start(fn ->
      text = Flagon.App.QueryText.extract(:query_editor, mode)
      Drafter.send_app_event(:run_text, text)
    end)

    {:noreply, state}
  end

  defp reconnect_and_retry(caller, target, query_text, timeout) do
    send(caller, {:query_reconnecting, target})
    Flagon.Connection.Manager.disconnect(target)

    case Flagon.Connection.Manager.connect(target) do
      {:ok, _} ->
        send(caller, {:connected, target})
        Flagon.Connection.Manager.switch(target)
        send(caller, {:query_complete, safe_execute(query_text, timeout)})

      {:error, reason} ->
        send(caller, {:connect_failed, target, reason})
    end
  end

  defp safe_execute(query_text, timeout) do
    Flagon.Query.Executor.execute_sync(query_text, timeout: timeout)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, {:exit, inspect(reason)}}
  end

  defp reconcile_connections(state, config, connections) do
    ids = Enum.map(connections, &Flagon.Config.qualified_name/1)
    statuses = Map.new(ids, fn id -> {id, Map.get(state.conn_statuses, id, :disconnected)} end)
    target = if state.query_target in ids, do: state.query_target, else: List.first(ids)

    added =
      Enum.reject(connections, fn conn ->
        Map.has_key?(state.conn_statuses, Flagon.Config.qualified_name(conn))
      end)

    base = %{state | config: config, connections: connections, conn_statuses: statuses, query_target: target}
    Enum.reduce(added, base, &start_connect/2)
  end

  defp start_connect(conn_config, state) do
    name = Flagon.Config.qualified_name(conn_config)
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

  defp load_columns_async(nil, _namespace, _table), do: :ok

  defp load_columns_async(target, namespace, table) do
    caller = self()

    Task.start(fn ->
      case Flagon.Connection.Manager.load_columns(target, namespace, table) do
        {:ok, columns} -> send(caller, {:columns_loaded, target, {:table, namespace, table}, columns})
        _ -> :ok
      end
    end)

    :ok
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

  defp editor_language(state) do
    case connection_type_for(state.query_target, state) do
      :kdb -> :kdb
      :postgres -> :sql
      :duckdb -> :sql
      _ -> nil
    end
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
    case Enum.find(state.connections, &(Flagon.Config.qualified_name(&1) == name)) do
      %{type: type} -> type
      _ -> nil
    end
  end

  defp connection_type_label(name, state) do
    case connection_type_for(name, state) do
      :kdb -> "KDB"
      :postgres -> "PostgreSQL"
      :duckdb -> "DuckDB"
      _ -> "?"
    end
  end

  defp init_editor_table do
    if :ets.whereis(@editor_table) == :undefined do
      :ets.new(@editor_table, [:named_table, :public, :set])
    end
  end

  defp save_editor(nil, _text), do: :ok

  defp save_editor(name, text) do
    :ets.insert(@editor_table, {name, text})
  end

  defp load_editor(nil), do: ""

  defp load_editor(name) do
    case :ets.lookup(@editor_table, name) do
      [{^name, text}] -> text
      _ -> ""
    end
  end

  defp export_csv(result, state) do
    path = Path.expand("~/Downloads/flagon_export_#{export_timestamp()}.csv")

    case Flagon.Export.CSV.export(result, path) do
      :ok -> {:ok, %{state | error: nil}}
      {:error, reason} -> {:ok, %{state | error: "Export failed: #{inspect(reason)}"}}
    end
  end

  defp export_timestamp do
    {{y, m, d}, {h, min, s}} = :calendar.local_time()

    :io_lib.format("~4..0B~2..0B~2..0B_~2..0B~2..0B~2..0B", [y, m, d, h, min, s])
    |> IO.iodata_to_binary()
  end
end
