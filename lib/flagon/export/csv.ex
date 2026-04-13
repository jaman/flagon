defmodule Flagon.Export.CSV do
  @moduledoc "CSV export using NimbleCSV."

  NimbleCSV.define(Flagon.Export.CSV.Parser, separator: ",", escape: "\"")

  alias Flagon.Query.Result

  @spec export(Result.t(), String.t()) :: :ok | {:error, term()}
  def export(%Result{} = result, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, to_iodata(result))
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  @spec to_iodata(Result.t()) :: iodata()
  def to_iodata(%Result{columns: columns, rows: rows}) do
    header = Enum.map(columns, & &1.name)

    data_rows =
      Enum.map(rows, fn row ->
        Enum.map(row, &stringify/1)
      end)

    Flagon.Export.CSV.Parser.dump_to_iodata([header | data_rows])
  end

  defp stringify(nil), do: ""
  defp stringify(value) when is_binary(value), do: value
  defp stringify(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp stringify(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp stringify(%Date{} = d), do: Date.to_string(d)
  defp stringify(%Time{} = t), do: Time.to_string(t)
  defp stringify(value), do: to_string(value)
end
