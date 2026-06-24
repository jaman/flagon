defmodule Flagon.App.ChartViewTest do
  use ExUnit.Case, async: true

  alias Flagon.App.ChartView
  alias Flagon.Query.Result

  defp result(columns, rows), do: %Result{columns: columns, rows: rows, row_count: length(rows)}

  test "chartable?/1 requires rows and at least one numeric column" do
    assert ChartView.chartable?(result([%{name: "v", type: :integer}], [[1]]))
    refute ChartView.chartable?(result([%{name: "v", type: :integer}], []))
    refute ChartView.chartable?(result([%{name: "s", type: :string}], [["a"]]))
  end

  test "auto_chart_data uses Drafter's :chart_type key and an image-capable renderer" do
    {data, opts} = ChartView.auto_chart_data(result([%{name: "v", type: :integer}], [[1], [2], [3]]))
    assert data == [1, 2, 3]
    assert opts[:chart_type] == :line
    assert opts[:renderer] == :auto
    refute Keyword.has_key?(opts, :type)
  end

  test "auto_chart_data uses a leading non-numeric column as x_labels" do
    columns = [%{name: "day", type: :string}, %{name: "v", type: :integer}]
    {data, opts} = ChartView.auto_chart_data(result(columns, [["mon", 10], ["tue", 20]]))
    assert data == [10, 20]
    assert opts[:x_labels] == ["mon", "tue"]
  end

  test "auto_chart_data returns one value-series per y column when several numeric columns exist" do
    columns = [%{name: "x", type: :integer}, %{name: "a", type: :integer}, %{name: "b", type: :integer}]
    {data, _opts} = ChartView.auto_chart_data(result(columns, [[1, 10, 100], [2, 20, 200]]))
    assert data == [[10, 20], [100, 200]]
  end

  test "auto_chart_data/2 shapes candlestick data as [open, high, low, close] rows" do
    columns = [
      %{name: "dt", type: :date},
      %{name: "open", type: :float},
      %{name: "high", type: :float},
      %{name: "low", type: :float},
      %{name: "close", type: :float}
    ]

    rows = [["d1", 10.0, 12.0, 9.0, 11.0], ["d2", 11.0, 13.0, 10.5, 12.0]]
    {data, opts} = ChartView.auto_chart_data(result(columns, rows), :candlestick)

    assert data == [[10.0, 12.0, 9.0, 11.0], [11.0, 13.0, 10.5, 12.0]]
    assert opts[:chart_type] == :candlestick
    assert opts[:x_labels] == ["d1", "d2"]
  end
end
