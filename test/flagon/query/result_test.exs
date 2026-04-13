defmodule Flagon.Query.ResultTest do
  use ExUnit.Case, async: true

  alias Flagon.Query.Result

  describe "from_maps/2" do
    test "converts list of maps to result" do
      rows = [
        %{"sym" => "AAPL", "price" => 182.5, "size" => 100},
        %{"sym" => "MSFT", "price" => 415.2, "size" => 200}
      ]

      result = Result.from_maps(rows, 42)

      assert result.row_count == 2
      assert result.execution_time_ms == 42
      assert length(result.columns) == 3
      assert Enum.map(result.columns, & &1.name) |> Enum.sort() == ["price", "size", "sym"]
    end

    test "handles empty list" do
      result = Result.from_maps([], 10)
      assert result.row_count == 0
      assert result.columns == []
      assert result.rows == []
    end

    test "infers types from first row" do
      rows = [%{"count" => 42, "name" => "test", "ratio" => 3.14}]
      result = Result.from_maps(rows, 0)

      types = Map.new(result.columns, fn c -> {c.name, c.type} end)
      assert types["count"] == :integer
      assert types["name"] == :string
      assert types["ratio"] == :float
    end
  end

  describe "from_scalar/2" do
    test "wraps scalar value" do
      result = Result.from_scalar(42, 5)
      assert result.row_count == 1
      assert result.columns == [%{name: "result", type: :integer}]
      assert result.rows == [[42]]
    end
  end

  describe "page/3" do
    test "returns correct page" do
      result = %Result{
        rows: Enum.map(1..100, &[&1]),
        row_count: 100
      }

      {page1, total} = Result.page(result, 1, 10)
      assert length(page1) == 10
      assert total == 10
      assert List.first(page1) == [1]
      assert List.last(page1) == [10]

      {page5, _} = Result.page(result, 5, 10)
      assert List.first(page5) == [41]
      assert List.last(page5) == [50]
    end

    test "clamps page number" do
      result = %Result{rows: [[1], [2], [3]], row_count: 3}
      {rows, total} = Result.page(result, 999, 10)
      assert total == 1
      assert length(rows) == 3
    end
  end

  describe "to_data_table_format/3" do
    test "converts to drafter data_table format" do
      result = %Result{
        columns: [%{name: "id", type: :integer}, %{name: "name", type: :string}],
        rows: [[1, "Alice"], [2, "Bob"]],
        row_count: 2
      }

      {columns, data, total_pages} = Result.to_data_table_format(result)

      assert length(columns) == 2
      assert Enum.at(columns, 0).key == :id
      assert Enum.at(columns, 0).label == "id"
      assert Enum.at(columns, 1).key == :name

      assert length(data) == 2
      assert Enum.at(data, 0).id == 1
      assert Enum.at(data, 0).name == "Alice"
      assert total_pages == 1
    end
  end

  describe "to_tsv/1" do
    test "formats as TSV" do
      result = %Result{
        columns: [%{name: "a", type: :integer}, %{name: "b", type: :string}],
        rows: [[1, "x"], [2, "y"]]
      }

      tsv = Result.to_tsv(result)
      assert tsv == "a\tb\n1\tx\n2\ty"
    end
  end

  describe "from_ecto/2" do
    test "converts Ecto query result" do
      ecto_result = %{
        columns: ["id", "name"],
        rows: [[1, "Alice"], [2, "Bob"]],
        num_rows: 2
      }

      result = Result.from_ecto(ecto_result, 15)
      assert result.row_count == 2
      assert result.execution_time_ms == 15
      assert length(result.columns) == 2
      assert Enum.at(result.columns, 0).name == "id"
    end
  end
end
