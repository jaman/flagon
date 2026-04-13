defmodule Flagon.Export.Clipboard do
  @moduledoc "Copy results to system clipboard as TSV."

  alias Flagon.Query.Result

  @spec copy(Result.t()) :: :ok | {:error, term()}
  def copy(%Result{} = result) do
    tsv = Result.to_tsv(result)

    case clipboard_command() do
      {:ok, {cmd, args}} ->
        port = Port.open({:spawn_executable, cmd}, [:binary, :exit_status, args: args])
        Port.command(port, tsv)
        Port.close(port)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp clipboard_command do
    case :os.type() do
      {:unix, :darwin} -> find_executable("pbcopy", [])
      {:unix, _} -> find_executable("xclip", ["-selection", "clipboard"])
      {:win32, _} -> find_executable("clip", [])
      _ -> {:error, :unsupported_platform}
    end
  end

  defp find_executable(name, args) do
    case System.find_executable(name) do
      nil -> {:error, {:executable_not_found, name}}
      path -> {:ok, {path, args}}
    end
  end
end
