defmodule Flagon.Connection.EctoAdapter do
  @moduledoc """
  Shared logic for Ecto-based database adapters (Postgres, DuckDB).
  Creates dynamic Ecto repos at runtime.
  """

  @registry :flagon_ecto_repos

  @spec start_registry() :: :ok
  def start_registry do
    if :ets.whereis(@registry) == :undefined do
      :ets.new(@registry, [:named_table, :public, :set])
    end

    :ok
  end

  @spec create_and_start_repo(String.t(), module(), keyword()) ::
          {:ok, module()} | {:error, term()}
  def create_and_start_repo(name, adapter, repo_opts) do
    start_registry()
    repo_module = repo_module_name(name)

    case :ets.lookup(@registry, name) do
      [{^name, ^repo_module}] ->
        {:ok, repo_module}

      _ ->
        define_repo(repo_module, adapter)
        start_repo(repo_module, name, repo_opts)
    end
  end

  @spec stop_repo(String.t()) :: :ok
  def stop_repo(name) do
    case :ets.lookup(@registry, name) do
      [{^name, repo_module}] ->
        repo_module.stop()
        :ets.delete(@registry, name)
        :ok

      _ ->
        :ok
    end
  end

  @spec query(String.t(), String.t()) ::
          {:ok, Flagon.Query.Result.t()} | {:error, term()}
  def query(name, query_string) do
    query(name, query_string, [])
  end

  @spec query(String.t(), String.t(), list()) ::
          {:ok, Flagon.Query.Result.t()} | {:error, term()}
  def query(name, query_string, params) do
    case :ets.lookup(@registry, name) do
      [{^name, repo_module}] ->
        started = System.monotonic_time(:millisecond)

        case Ecto.Adapters.SQL.query(repo_module, query_string, params) do
          {:ok, result} ->
            elapsed = System.monotonic_time(:millisecond) - started
            {:ok, Flagon.Query.Result.from_ecto(result, elapsed)}

          {:error, %Postgrex.Error{postgres: %{message: msg}}} ->
            {:error, msg}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, :not_connected}
    end
  end

  @spec stream_query(String.t(), String.t(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_query(name, query_string, opts) do
    case :ets.lookup(@registry, name) do
      [{^name, repo_module}] ->
        max_rows = Keyword.get(opts, :max_rows, 1000)

        stream =
          repo_module.transaction(fn ->
            Ecto.Adapters.SQL.stream(repo_module, query_string, [], max_rows: max_rows)
            |> Enum.to_list()
          end)

        case stream do
          {:ok, results} -> {:ok, results}
          {:error, reason} -> {:error, reason}
        end

      _ ->
        {:error, :not_connected}
    end
  end

  defp repo_module_name(name) do
    safe_name =
      name
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")
      |> Macro.camelize()

    Module.concat([Flagon, Repo, safe_name])
  end

  defp define_repo(repo_module, adapter) do
    unless Code.ensure_loaded?(repo_module) do
      contents =
        quote do
          use Ecto.Repo,
            otp_app: :flagon,
            adapter: unquote(adapter)
        end

      Module.create(repo_module, contents, Macro.Env.location(__ENV__))
    end
  end

  defp start_repo(repo_module, name, repo_opts) do
    child_spec = %{
      id: repo_module,
      start: {repo_module, :start_link, [repo_opts]},
      type: :supervisor
    }

    case Supervisor.start_child(Flagon.Supervisor, child_spec) do
      {:ok, _pid} ->
        :ets.insert(@registry, {name, repo_module})
        {:ok, repo_module}

      {:error, {:already_started, _pid}} ->
        :ets.insert(@registry, {name, repo_module})
        {:ok, repo_module}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
