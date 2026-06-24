defmodule Flagon.App.ConnectionDialog do
  use Drafter.Screen

  def mount(%{connections: connections}) do
    %{
      connections: connections,
      editing: nil,
      form: blank_form(),
      error: nil
    }
  end

  def render(%{editing: nil} = state) do
    vertical([
      label("Connections", style: %{bold: true}),
      render_connection_list(state.connections),
      horizontal(
        [
          button("Add New", on_click: :add_new, compact: true),
          button("Close", on_click: :close, compact: true)
        ],
        gap: 1,
        height: 1
      )
    ])
  end

  def render(state) do
    vertical([
      label("Edit Connection", style: %{bold: true}),
      render_error(state.error),
      render_form(state.form),
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

  def handle_event({:key, :escape}, _data, state) do
    case state.editing do
      nil ->
        Drafter.send_app_event(:connection_result, {:updated, state.connections})
        {:pop, {:connections, state.connections}}

      _ ->
        {:ok, %{state | editing: nil, form: blank_form(), error: nil}}
    end
  end

  def handle_event(:close, _data, state) do
    Drafter.send_app_event(:connection_result, {:updated, state.connections})
    {:pop, {:connections, state.connections}}
  end

  def handle_event(:add_new, _data, state) do
    {:ok, %{state | editing: length(state.connections), form: blank_form(), error: nil}}
  end

  def handle_event(:cancel, _data, state) do
    {:ok, %{state | editing: nil, form: blank_form(), error: nil}}
  end

  def handle_event(:save, _data, state) do
    case validate_form(state.form) do
      {:ok, conn_config} ->
        connections = save_connection(state.connections, state.editing, conn_config)
        {:ok, %{state | connections: connections, editing: nil, form: blank_form(), error: nil}}

      {:error, reason} ->
        {:ok, %{state | error: reason}}
    end
  end

  def handle_event(:edit, index, state) when is_integer(index) do
    conn = Enum.at(state.connections, index)
    form = connection_to_form(conn)
    {:ok, %{state | editing: index, form: form, error: nil}}
  end

  def handle_event(:remove, index, state) when is_integer(index) do
    connections = List.delete_at(state.connections, index)
    {:ok, %{state | connections: connections}}
  end

  def handle_event(:form_name, value, state), do: {:ok, put_in(state.form.name, value)}
  def handle_event(:form_host, value, state), do: {:ok, put_in(state.form.host, value)}
  def handle_event(:form_port, value, state), do: {:ok, put_in(state.form.port, value)}
  def handle_event(:form_dsn, value, state), do: {:ok, put_in(state.form.dsn, value)}
  def handle_event(:form_path, value, state), do: {:ok, put_in(state.form.path, value)}

  def handle_event(:form_type, %{id: type_id}, state) do
    {:ok, put_in(state.form.type, type_id)}
  end

  def handle_event(:form_type, type, state) when is_binary(type) do
    {:ok, put_in(state.form.type, type)}
  end

  def handle_event(_event, _data, state), do: {:noreply, state}

  defp render_connection_list([]) do
    label("No connections configured.", style: %{dim: true})
  end

  defp render_connection_list(connections) do
    connections
    |> Enum.with_index()
    |> Enum.map(fn {conn, idx} ->
      horizontal(
        [
          label("#{conn.name} (#{conn.type})", flex: 1),
          button("Edit", on_click: {:edit, idx}, compact: true),
          button("Remove", on_click: {:remove, idx}, compact: true)
        ],
        gap: 1,
        height: 1
      )
    end)
    |> vertical()
  end

  defp render_error(nil), do: label("")

  defp render_error(message) do
    label(message, style: %{fg: {255, 80, 80}})
  end

  defp render_form(form) do
    type_options = [
      {"kdb", "kdb"},
      {"postgres", "postgres"},
      {"duckdb", "duckdb"}
    ]

    base_fields = [
      horizontal([label("Name:", width: 12), text_input(id: :form_name, bind: :name, on_change: :form_name)], height: 1),
      horizontal([label("Type:", width: 12), option_list(type_options, id: :form_type, on_select: :form_type, height: 3)], height: 3)
    ]

    type_fields =
      case form.type do
        "kdb" ->
          [
            horizontal([label("Host:", width: 12), text_input(id: :form_host, bind: :host, on_change: :form_host)], height: 1),
            horizontal([label("Port:", width: 12), text_input(id: :form_port, bind: :port, on_change: :form_port)], height: 1)
          ]

        "postgres" ->
          [
            horizontal([label("DSN:", width: 12), text_input(id: :form_dsn, bind: :dsn, on_change: :form_dsn)], height: 1)
          ]

        "duckdb" ->
          [
            horizontal([label("Path:", width: 12), text_input(id: :form_path, bind: :path, on_change: :form_path)], height: 1)
          ]

        _ ->
          []
      end

    vertical(base_fields ++ type_fields)
  end

  defp blank_form do
    %{name: "", type: "kdb", host: "", port: "", dsn: "", path: ""}
  end

  defp connection_to_form(conn) do
    %{
      name: to_string(conn.name),
      type: to_string(conn.type),
      host: to_string(Map.get(conn, :host, "")),
      port: to_string(Map.get(conn, :port, "")),
      dsn: to_string(Map.get(conn, :dsn, "")),
      path: to_string(Map.get(conn, :path, ""))
    }
  end

  defp validate_form(%{name: name}) when name in ["", nil] do
    {:error, "Name is required"}
  end

  defp validate_form(%{type: "kdb", host: host}) when host in ["", nil] do
    {:error, "Host is required for KDB connections"}
  end

  defp validate_form(%{type: "kdb", port: port}) when port in ["", nil] do
    {:error, "Port is required for KDB connections"}
  end

  defp validate_form(%{type: "postgres", dsn: dsn}) when dsn in ["", nil] do
    {:error, "DSN is required for PostgreSQL connections"}
  end

  defp validate_form(%{type: "duckdb", path: path}) when path in ["", nil] do
    {:error, "Path is required for DuckDB connections"}
  end

  defp validate_form(form) do
    config =
      %{name: form.name, type: String.to_existing_atom(form.type)}
      |> maybe_put(:host, form.host)
      |> maybe_put(:port, parse_port(form.port))
      |> maybe_put(:dsn, form.dsn)
      |> maybe_put(:path, form.path)

    {:ok, config}
  end

  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_port(""), do: nil

  defp parse_port(port_str) do
    case Integer.parse(port_str) do
      {port, ""} -> port
      _ -> port_str
    end
  end

  defp save_connection(connections, index, config) when index >= length(connections) do
    connections ++ [config]
  end

  defp save_connection(connections, index, config) do
    List.replace_at(connections, index, config)
  end
end
