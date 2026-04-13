defmodule Flagon.Export do
  @moduledoc "Dispatches export operations to format-specific modules."

  alias Flagon.Query.Result

  @spec export(Result.t(), String.t(), :csv | :excel) :: :ok | {:error, term()}
  def export(result, path, :csv), do: Flagon.Export.CSV.export(result, path)
  def export(result, path, :excel), do: Flagon.Export.Excel.export(result, path)

  @spec copy_to_clipboard(Result.t()) :: :ok | {:error, term()}
  def copy_to_clipboard(result), do: Flagon.Export.Clipboard.copy(result)
end
