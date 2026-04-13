defmodule Flagon.App do
  @moduledoc """
  Main TUI application for Flagon.
  """

  use Drafter.App

  @editor_table :flagon_editor_state

  def mount(_props) do
    config = Process.get(:flagon_config, Flagon.Config.load())

    conn_names =
      Enum.map(config.connections, fn c ->
        {to_string(c.name), to_string(c.name)}
      end)

    first_name =
      case config.connections do
        [first | _] -> to_string(first.name)
        [] -> nil
      end

    init_editor_table()

    %{
      config: config,
      connections: config.connections,
      conn_names: conn_names,
      conn_schemas: %{},
      conn_statuses: %{},
      query_target: first_name,
      query_text: load_editor(first_name),
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
      footer()
    ])
  end

  def keybindings do
    [
      {"F5", "Run"},
      {"Ctrl+R", "Refresh"},
      {"Ctrl+Q", "Quit"}
    ]
  end

  def handle_event({:key, :f5}, state), do: run_query(state)

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

  def handle_event(:connection_selected, conn_name, state) when is_binary(conn_name) do
    switch_connection(conn_name, state)
  end

  def handle_event(:connection_selected, %{id: conn_name}, state) do
    switch_connection(to_string(conn_name), state)
  end

  def handle_event(:run_query, _data, state), do: run_query(state)

  def handle_event(:schema_node_selected, [%{id: {:table, _, _}, metadata: meta} | _], state) do
    conn_type = connection_type_for(state.query_target, state)
    node = %{type: :table, metadata: meta}
    query = Flagon.Schema.default_query_for(node, conn_type, state.page_size)
    run_query(%{state | query_text: query})
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

  def handle_event(:quick_select_top, _data, state), do: {:noreply, state}
  def handle_event(:quick_count, _data, state), do: {:noreply, state}

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
    vertical([
      label("Servers", style: %{bold: true}),
      option_list(
        state.conn_names,
        id: :conn_list,
        on_select: :connection_selected,
        height: max(3, length(state.conn_names) + 1)
      ),
      label("", height: 1),
      render_schema_tree(state)
    ])
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
          if(state.executing?, do: "Running...", else: "Run"),
          on_click: :run_query,
          compact: true,
          style: %{bold: true}
        ),
        button("Refresh", on_click: :refresh_schema, compact: true)
      ],
      gap: 1,
      height: 1
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

  defp run_query(state) do
    query_text = String.trim(state.query_text || "")

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

              {:error, _} ->
                send(caller, {:query_reconnecting, target})
                Flagon.Connection.Manager.disconnect(target)

                case Flagon.Connection.Manager.connect(target) do
                  {:ok, _} ->
                    send(caller, {:connected, target})
                    Flagon.Connection.Manager.switch(target)
                    retry = safe_execute(query_text, timeout)
                    send(caller, {:query_complete, retry})

                  {:error, reason} ->
                    send(caller, {:connect_failed, target, reason})
                end
            end
          end)

        {:ok, %{state | executing?: true, error: nil, query_task: task}}
    end
  end

  defp safe_execute(query_text, timeout) do
    Flagon.Query.Executor.execute_sync(query_text, timeout: timeout)
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, {:exit, inspect(reason)}}
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
end
