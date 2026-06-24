defmodule Flagon.App.ChartView do
  @moduledoc """
  Derives chart data and options for a query `Result`, driving Drafter's chart
  widget. Numeric columns become the plotted series; a leading non-numeric column
  becomes the X-axis labels. Charts request `renderer: :auto` so they render as
  true terminal images (kitty/iTerm2/sixel) where supported, falling back to
  braille elsewhere.
  """

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

  @spec auto_chart_data(Result.t(), atom()) :: {term(), keyword()}
  def auto_chart_data(result, chart_type \\ :line)

  def auto_chart_data(%Result{rows: rows} = result, :candlestick) do
    idxs = result |> numeric_columns() |> Enum.map(&elem(&1, 0)) |> Enum.take(4)
    data = Enum.map(rows, fn row -> Enum.map(idxs, fn idx -> safe_number(Enum.at(row, idx)) end) end)
    {data, base_opts(:candlestick, result, rows)}
  end

  def auto_chart_data(%Result{rows: rows} = result, chart_type) do
    {series_for(numeric_columns(result), rows), base_opts(chart_type, result, rows)}
  end

  defp base_opts(chart_type, result, rows) do
    [chart_type: chart_type, renderer: :auto, height: :auto, show_axes: true]
    |> maybe_put_x_labels(result, rows)
  end

  defp series_for([], _rows), do: []
  defp series_for([{idx, _col}], rows), do: column_values(rows, idx)
  defp series_for([{_x_idx, _}, {y_idx, _}], rows), do: column_values(rows, y_idx)

  defp series_for([{_x_idx, _} | y_cols], rows) do
    Enum.map(y_cols, fn {idx, _col} -> column_values(rows, idx) end)
  end

  defp maybe_put_x_labels(opts, result, rows) do
    case first_non_numeric_index(result) do
      nil -> opts
      idx -> Keyword.put(opts, :x_labels, Enum.map(rows, fn row -> to_string(Enum.at(row, idx)) end))
    end
  end

  defp first_non_numeric_index(%Result{columns: columns}) do
    columns
    |> Enum.with_index()
    |> Enum.find_value(fn {col, idx} -> if col.type not in @numeric_types, do: idx end)
  end

  defp column_values(rows, idx), do: Enum.map(rows, fn row -> safe_number(Enum.at(row, idx)) end)

  defp safe_number(val) when is_number(val), do: val
  defp safe_number(_val), do: 0
end
