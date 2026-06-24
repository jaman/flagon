defmodule Flagon.App.ChartView do
  alias Flagon.Query.Result

  @numeric_types [:integer, :float]

  @spec chartable?(Result.t()) :: boolean()
  def chartable?(%Result{columns: columns, rows: rows}) do
    length(rows) > 0 and Enum.any?(columns, fn %{type: type} -> type in @numeric_types end)
  end

  @spec numeric_columns(Result.t()) :: [{non_neg_integer(), map()}]
  def numeric_columns(%Result{columns: columns}) do
    columns
    |> Enum.with_index()
    |> Enum.filter(fn {col, _idx} -> col.type in @numeric_types end)
    |> Enum.map(fn {col, idx} -> {idx, col} end)
  end

  @spec auto_chart_data(Result.t()) :: {term(), keyword()}
  def auto_chart_data(%Result{rows: rows} = result) do
    numeric_cols = numeric_columns(result)
    opts = [type: :line, height: :auto, show_axes: true]

    case numeric_cols do
      [] ->
        {[], opts}

      [{single_idx, _}] ->
        data = Enum.map(rows, fn row -> safe_number(Enum.at(row, single_idx)) end)
        {data, opts}

      [{_x_idx, _}, {y_idx, _}] ->
        data = Enum.map(rows, fn row -> safe_number(Enum.at(row, y_idx)) end)
        {data, opts}

      [{_x_idx, _} | y_cols] ->
        data =
          Enum.map(y_cols, fn {col_idx, col_info} ->
            series = Enum.map(rows, fn row -> safe_number(Enum.at(row, col_idx)) end)
            {col_info.name, series}
          end)

        {data, opts}
    end
  end

  defp safe_number(val) when is_number(val), do: val
  defp safe_number(_val), do: 0
end
