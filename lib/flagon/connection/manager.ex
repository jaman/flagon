defmodule Flagon.Connection.Manager do
  @moduledoc """
  GenServer managing active database connections.
  """

  use GenServer

  defstruct connections: %{},
            active: nil,
            configs: %{}

  @type connection_state :: %{
          conn: Flagon.Connection.conn() | nil,
          adapter: module(),
          config: map(),
          status: :connected | :disconnected | :connecting | :error,
          error: term() | nil,
          schema_cache: [Flagon.Schema.schema_node()] | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec load_connections([Flagon.Config.connection_config()]) :: :ok
  def load_connections(connection_configs) do
    GenServer.call(__MODULE__, {:load_connections, connection_configs})
  end

  @spec connect(String.t() | atom()) :: {:ok, Flagon.Connection.conn()} | {:error, term()}
  def connect(name) do
    GenServer.call(__MODULE__, {:connect, to_string(name)}, 15_000)
  end

  @spec disconnect(String.t() | atom()) :: :ok
  def disconnect(name) do
    GenServer.call(__MODULE__, {:disconnect, to_string(name)})
  end

  @spec switch(String.t() | atom()) :: :ok | {:error, term()}
  def switch(name) do
    GenServer.call(__MODULE__, {:switch, to_string(name)})
  end

  @spec active_connection() :: {String.t(), connection_state()} | nil
  def active_connection do
    GenServer.call(__MODULE__, :active_connection)
  end

  @spec query(String.t()) :: Flagon.Connection.query_result()
  def query(query_string) do
    GenServer.call(__MODULE__, {:query, query_string}, 60_000)
  end

  @spec query(String.t(), list()) :: Flagon.Connection.query_result()
  def query(query_string, params) do
    GenServer.call(__MODULE__, {:query, query_string, params}, 60_000)
  end

  @spec introspect() :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def introspect do
    GenServer.call(__MODULE__, :introspect, 30_000)
  end

  @spec introspect_connection(String.t()) :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def introspect_connection(name) do
    GenServer.call(__MODULE__, {:introspect_connection, to_string(name)}, 30_000)
  end

  @spec refresh_schema() :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def refresh_schema do
    GenServer.call(__MODULE__, :refresh_schema, 30_000)
  end

  @spec refresh_schema_for(String.t()) :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def refresh_schema_for(name) do
    GenServer.call(__MODULE__, {:refresh_schema_for, to_string(name)}, 30_000)
  end

  @spec list_connections() :: [{String.t(), connection_state()}]
  def list_connections do
    GenServer.call(__MODULE__, :list_connections)
  end

  @spec connection_type() :: :kdb | :postgres | :duckdb | nil
  def connection_type do
    GenServer.call(__MODULE__, :connection_type)
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call({:load_connections, configs}, _from, state) do
    connections =
      Map.new(configs, fn config ->
        name = to_string(config.name)
        adapter = Flagon.Connection.adapter_for(config.type)

        {name,
         %{
           conn: nil,
           adapter: adapter,
           config: config,
           status: :disconnected,
           error: nil,
           schema_cache: nil
         }}
      end)

    {:reply, :ok, %{state | connections: connections}}
  end

  @impl true
  def handle_call({:connect, name}, _from, state) do
    case Map.get(state.connections, name) do
      nil ->
        {:reply, {:error, :unknown_connection}, state}

      %{status: :connected, conn: conn} ->
        {:reply, {:ok, conn}, %{state | active: name}}

      conn_state ->
        case conn_state.adapter.connect(conn_state.config) do
          {:ok, conn} ->
            updated = %{conn_state | conn: conn, status: :connected, error: nil}
            connections = Map.put(state.connections, name, updated)
            {:reply, {:ok, conn}, %{state | connections: connections, active: name}}

          {:error, reason} = error ->
            updated = %{conn_state | status: :error, error: reason}
            connections = Map.put(state.connections, name, updated)
            {:reply, error, %{state | connections: connections}}
        end
    end
  end

  @impl true
  def handle_call({:disconnect, name}, _from, state) do
    case Map.get(state.connections, name) do
      nil ->
        {:reply, :ok, state}

      %{status: :connected} = conn_state ->
        conn_state.adapter.disconnect(conn_state.conn)
        updated = %{conn_state | conn: nil, status: :disconnected, schema_cache: nil}
        connections = Map.put(state.connections, name, updated)
        active = if state.active == name, do: nil, else: state.active
        {:reply, :ok, %{state | connections: connections, active: active}}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:switch, name}, _from, state) do
    if Map.has_key?(state.connections, name) do
      {:reply, :ok, %{state | active: name}}
    else
      {:reply, {:error, :unknown_connection}, state}
    end
  end

  @impl true
  def handle_call(:active_connection, _from, state) do
    result =
      case state.active do
        nil -> nil
        name -> {name, Map.get(state.connections, name)}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:query, query_string}, _from, state) do
    result = with_active_connection(state, fn conn_state ->
      conn_state.adapter.query(conn_state.conn, query_string)
    end)

    {:reply, result, state}
  end

  @impl true
  def handle_call({:query, query_string, params}, _from, state) do
    result = with_active_connection(state, fn conn_state ->
      conn_state.adapter.query(conn_state.conn, query_string, params)
    end)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:introspect, _from, state) do
    case state.active do
      nil ->
        {:reply, {:error, :no_active_connection}, state}

      name ->
        conn_state = Map.get(state.connections, name)

        case conn_state.schema_cache do
          nil ->
            case conn_state.adapter.introspect(conn_state.conn) do
              {:ok, schema} ->
                updated = %{conn_state | schema_cache: schema}
                connections = Map.put(state.connections, name, updated)
                {:reply, {:ok, schema}, %{state | connections: connections}}

              error ->
                {:reply, error, state}
            end

          cached ->
            {:reply, {:ok, cached}, state}
        end
    end
  end

  @impl true
  def handle_call(:refresh_schema, _from, state) do
    case state.active do
      nil ->
        {:reply, {:error, :no_active_connection}, state}

      name ->
        conn_state = Map.get(state.connections, name)

        case conn_state.adapter.introspect(conn_state.conn) do
          {:ok, schema} ->
            updated = %{conn_state | schema_cache: schema}
            connections = Map.put(state.connections, name, updated)
            {:reply, {:ok, schema}, %{state | connections: connections}}

          error ->
            {:reply, error, state}
        end
    end
  end

  @impl true
  def handle_call({:introspect_connection, name}, _from, state) do
    case Map.get(state.connections, name) do
      nil ->
        {:reply, {:error, :unknown_connection}, state}

      %{status: :connected} = conn_state ->
        case conn_state.schema_cache do
          nil ->
            case conn_state.adapter.introspect(conn_state.conn) do
              {:ok, schema} ->
                updated = %{conn_state | schema_cache: schema}
                connections = Map.put(state.connections, name, updated)
                {:reply, {:ok, schema}, %{state | connections: connections}}

              error ->
                {:reply, error, state}
            end

          cached ->
            {:reply, {:ok, cached}, state}
        end

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call({:refresh_schema_for, name}, _from, state) do
    case Map.get(state.connections, name) do
      nil ->
        {:reply, {:error, :unknown_connection}, state}

      %{status: :connected} = conn_state ->
        case conn_state.adapter.introspect(conn_state.conn) do
          {:ok, schema} ->
            updated = %{conn_state | schema_cache: schema}
            connections = Map.put(state.connections, name, updated)
            {:reply, {:ok, schema}, %{state | connections: connections}}

          error ->
            {:reply, error, state}
        end

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  @impl true
  def handle_call(:list_connections, _from, state) do
    {:reply, Map.to_list(state.connections), state}
  end

  @impl true
  def handle_call(:connection_type, _from, state) do
    result =
      case state.active do
        nil -> nil
        name -> get_in(state.connections, [name, :config, :type])
      end

    {:reply, result, state}
  end

  defp with_active_connection(state, fun) do
    case state.active do
      nil -> {:error, :no_active_connection}
      name ->
        case Map.get(state.connections, name) do
          %{status: :connected} = conn_state -> fun.(conn_state)
          _ -> {:error, :not_connected}
        end
    end
  end
end
