defmodule Flagon.Schema.Kdb do
  @moduledoc """
  KDB+ schema introspection via ExeQute.
  """

  @spec introspect(pid() | atom()) :: {:ok, [Flagon.Schema.schema_node()]} | {:error, term()}
  def introspect(conn) do
    clear_cache(conn)

    user_namespaces =
      case ExeQute.namespaces(conn) do
        {:ok, ns} -> ns
        _ -> []
      end

    all_namespaces = ["."] ++ Enum.reject(user_namespaces, &(&1 == "."))

    nodes =
      Enum.map(all_namespaces, fn ns ->
        %{
          id: {:ns, ns},
          label: ns,
          type: :namespace,
          children: load_namespace_children(conn, ns),
          metadata: %{namespace: ns}
        }
      end)

    {:ok, nodes}
  end

  defp clear_cache(conn) do
    ExeQute.Connection.clear_cache(conn)
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  @spec load_namespace_children(pid() | atom(), String.t()) :: [Flagon.Schema.schema_node()]
  def load_namespace_children(conn, namespace) do
    tables = load_tables(conn, namespace)
    functions = load_functions(conn, namespace)
    variables = load_variables(conn, namespace)

    tables ++ functions ++ variables
  end

  defp load_tables(conn, namespace) do
    ns_arg = if namespace == ".", do: nil, else: namespace

    case safe_call(fn -> ExeQute.tables(conn, ns_arg) end) do
      {:ok, table_names} when is_list(table_names) ->
        Enum.map(table_names, fn name ->
          %{
            id: {:table, namespace, name},
            label: name,
            type: :table,
            children: :lazy,
            metadata: %{namespace: namespace, table: name}
          }
        end)

      _ ->
        []
    end
  end

  @spec columns(pid() | atom(), String.t(), String.t()) :: [Flagon.Schema.schema_node()]
  def columns(conn, namespace, table) do
    load_columns(conn, qualified_name(namespace, table))
  end

  defp load_columns(conn, table_name) do
    case safe_call(fn -> ExeQute.query(conn, "meta #{table_name}") end) do
      {:ok, rows} when is_list(rows) ->
        Enum.map(rows, fn row ->
          col_name = Map.get(row, "c", Map.get(row, :c, "?"))
          col_type = Map.get(row, "t", Map.get(row, :t, "?"))

          %{
            id: {:col, table_name, col_name},
            label: "#{col_name} : #{col_type}",
            type: :column,
            children: [],
            metadata: %{column: col_name, kdb_type: col_type}
          }
        end)

      _ ->
        []
    end
  end

  defp load_functions(conn, namespace) do
    ns_arg = if namespace == ".", do: nil, else: namespace

    case safe_call(fn -> ExeQute.functions(conn, ns_arg) end) do
      {:ok, funcs} when is_list(funcs) ->
        Enum.map(funcs, fn func ->
          name = Map.get(func, "name", "?")
          params = Map.get(func, "params", [])
          param_str = Enum.join(params, ";")

          %{
            id: {:func, namespace, name},
            label: "#{name}[#{param_str}]",
            type: :function,
            children: [],
            metadata: %{
              namespace: namespace,
              function: name,
              params: params,
              body: Map.get(func, "body", "")
            }
          }
        end)

      _ ->
        []
    end
  end

  defp load_variables(conn, namespace) do
    ns_arg = if namespace == ".", do: nil, else: namespace

    case safe_call(fn -> ExeQute.variables(conn, ns_arg) end) do
      {:ok, vars} when is_list(vars) ->
        Enum.map(vars, fn name ->
          %{
            id: {:var, namespace, name},
            label: to_string(name),
            type: :variable,
            children: [],
            metadata: %{namespace: namespace, variable: name}
          }
        end)

      _ ->
        []
    end
  end

  defp safe_call(fun) do
    fun.()
  rescue
    _ -> {:error, :introspection_failed}
  catch
    _, _ -> {:error, :introspection_failed}
  end

  defp qualified_name(".", name), do: name
  defp qualified_name(".root", name), do: name
  defp qualified_name(ns, name), do: "#{ns}.#{name}"
end
