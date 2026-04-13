defmodule Flagon.Export.Excel do
  @moduledoc "Excel export using Elixlsx."

  alias Flagon.Query.Result

  @spec export(Result.t(), String.t()) :: :ok | {:error, term()}
  def export(%Result{} = result, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      result
      |> build_workbook()
      |> Elixlsx.write_to(path)
      |> case do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp build_workbook(%Result{columns: columns, rows: rows}) do
    header_row = Enum.map(columns, fn col -> [col.name, bold: true] end)
    data_rows = Enum.map(rows, fn row -> Enum.map(row, &to_excel_value/1) end)

    sheet = %Elixlsx.Sheet{name: "Query Results", rows: [header_row | data_rows]}
    %Elixlsx.Workbook{sheets: [sheet]}
  end

  defp to_excel_value(nil), do: ""
  defp to_excel_value(value) when is_number(value), do: value
  defp to_excel_value(value) when is_boolean(value), do: value
  defp to_excel_value(value) when is_binary(value), do: value
  defp to_excel_value(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp to_excel_value(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp to_excel_value(%Date{} = d), do: Date.to_string(d)
  defp to_excel_value(%Time{} = t), do: Time.to_string(t)
  defp to_excel_value(value), do: inspect(value)
end
