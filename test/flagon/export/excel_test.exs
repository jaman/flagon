defmodule Flagon.Export.ExcelTest do
  use ExUnit.Case, async: true

  alias Flagon.Export.Excel
  alias Flagon.Query.Result

  @sample_result %Result{
    columns: [%{name: "id", type: :integer}, %{name: "name", type: :string}, %{name: "score", type: :float}],
    rows: [[1, "Alice", 95.5], [2, "Bob", 87.3]],
    row_count: 2,
    execution_time_ms: 10
  }

  describe "export/2" do
    test "writes xlsx file to disk" do
      path = Path.join(System.tmp_dir!(), "flagon_test_#{System.unique_integer([:positive])}.xlsx")

      on_exit(fn -> File.rm(path) end)

      assert :ok = Excel.export(@sample_result, path)
      assert File.exists?(path)
      assert File.stat!(path).size > 0
    end

    test "creates parent directories" do
      dir = Path.join(System.tmp_dir!(), "flagon_excel_#{System.unique_integer([:positive])}")
      path = Path.join(dir, "export.xlsx")

      on_exit(fn -> File.rm_rf(dir) end)

      assert :ok = Excel.export(@sample_result, path)
      assert File.exists?(path)
    end

    test "handles empty result" do
      result = %Result{columns: [], rows: [], row_count: 0}
      path = Path.join(System.tmp_dir!(), "flagon_empty_#{System.unique_integer([:positive])}.xlsx")

      on_exit(fn -> File.rm(path) end)

      assert :ok = Excel.export(result, path)
      assert File.exists?(path)
    end

    test "handles nil values" do
      result = %Result{
        columns: [%{name: "a", type: :string}],
        rows: [[nil]],
        row_count: 1
      }

      path = Path.join(System.tmp_dir!(), "flagon_nil_#{System.unique_integer([:positive])}.xlsx")

      on_exit(fn -> File.rm(path) end)

      assert :ok = Excel.export(result, path)
      assert File.exists?(path)
    end
  end
end
