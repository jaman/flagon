defmodule Flagon.Export.Stream do
  alias Flagon.Query.Result

  @chunk_size 1000

  NimbleCSV.define(Flagon.Export.Stream.CSVWriter, separator: ",", escape: "\"")
  NimbleCSV.define(Flagon.Export.Stream.TSVWriter, separator: "\t", escape: "\"")

  @spec export_csv_stream(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def export_csv_stream(_connection_name, query_string, opts \\ []) do
    path = Keyword.get(opts, :path, default_path())

    case Flagon.Connection.Manager.query(query_string) do
      {:ok, %Result{} = result} ->
        export_to_file(result, path, opts)

      {:error, _} = error ->
        error
    end
  end

  @spec export_to_file(Result.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def export_to_file(%Result{columns: columns, rows: rows}, path, opts \\ []) do
    format = Keyword.get(opts, :format, :csv)
    writer = writer_for(format)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      file = File.open!(path, [:write, :utf8])

      try do
        header = Enum.map(columns, & &1.name)
        IO.binwrite(file, writer.dump_to_iodata([header]))

        rows
        |> Enum.chunk_every(@chunk_size)
        |> Enum.each(fn chunk ->
          csv_rows = Enum.map(chunk, fn row -> Enum.map(row, &stringify/1) end)
          IO.binwrite(file, writer.dump_to_iodata(csv_rows))
        end)

        :ok
      after
        File.close(file)
      end
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp writer_for(:tsv), do: Flagon.Export.Stream.TSVWriter
  defp writer_for(_), do: Flagon.Export.Stream.CSVWriter

  defp default_path do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    Path.expand("~/Downloads/flagon_stream_#{timestamp}.csv")
  end

  defp stringify(nil), do: ""
  defp stringify(value) when is_binary(value), do: value
  defp stringify(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp stringify(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M:%S")
  defp stringify(%Date{} = d), do: Date.to_string(d)
  defp stringify(%Time{} = t), do: Time.to_string(t)
  defp stringify(value), do: to_string(value)
end
