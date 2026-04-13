defmodule Flagon.Export.CSVTest do
  use ExUnit.Case, async: true

  alias Flagon.Export.CSV
  alias Flagon.Query.Result

  @sample_result %Result{
    columns: [%{name: "id", type: :integer}, %{name: "name", type: :string}, %{name: "score", type: :float}],
    rows: [[1, "Alice", 95.5], [2, "Bob", 87.3], [3, "Carol", 91.0]],
    row_count: 3,
    execution_time_ms: 42
  }

  describe "to_iodata/1" do
    test "generates valid CSV with header and data rows" do
      csv = CSV.to_iodata(@sample_result) |> IO.iodata_to_binary()
      lines = String.split(csv, "\n", trim: true)

      assert length(lines) == 4
      assert Enum.at(lines, 0) == "id,name,score"
      assert Enum.at(lines, 1) == "1,Alice,95.5"
      assert Enum.at(lines, 2) == "2,Bob,87.3"
      assert Enum.at(lines, 3) == "3,Carol,91.0"
    end

    test "escapes values containing commas" do
      result = %Result{
        columns: [%{name: "val", type: :string}],
        rows: [["hello, world"]],
        row_count: 1
      }

      csv = CSV.to_iodata(result) |> IO.iodata_to_binary()
      lines = String.split(csv, "\n", trim: true)

      assert Enum.at(lines, 1) == "\"hello, world\""
    end

    test "handles nil values as empty strings" do
      result = %Result{
        columns: [%{name: "a", type: :string}, %{name: "b", type: :integer}],
        rows: [[nil, 1], ["x", nil]],
        row_count: 2
      }

      csv = CSV.to_iodata(result) |> IO.iodata_to_binary()
      lines = String.split(csv, "\n", trim: true)

      assert Enum.at(lines, 1) == ",1"
      assert Enum.at(lines, 2) == "x,"
    end

    test "handles empty result" do
      result = %Result{columns: [], rows: [], row_count: 0}
      csv = CSV.to_iodata(result) |> IO.iodata_to_binary()

      assert csv == "\n"
    end
  end

  describe "export/2" do
    test "writes CSV file to disk" do
      path = Path.join(System.tmp_dir!(), "flagon_test_#{System.unique_integer([:positive])}.csv")

      on_exit(fn -> File.rm(path) end)

      assert :ok = CSV.export(@sample_result, path)
      assert File.exists?(path)

      content = File.read!(path)
      lines = String.split(content, "\n", trim: true)

      assert length(lines) == 4
      assert Enum.at(lines, 0) == "id,name,score"
    end

    test "creates parent directories" do
      dir = Path.join(System.tmp_dir!(), "flagon_nested_#{System.unique_integer([:positive])}")
      path = Path.join(dir, "export.csv")

      on_exit(fn -> File.rm_rf(dir) end)

      assert :ok = CSV.export(@sample_result, path)
      assert File.exists?(path)
    end
  end
end
