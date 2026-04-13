defmodule Flagon.Export.ClipboardTest do
  use ExUnit.Case, async: true

  alias Flagon.Query.Result

  describe "tsv generation for clipboard" do
    test "produces correct TSV from result" do
      result = %Result{
        columns: [%{name: "id", type: :integer}, %{name: "name", type: :string}],
        rows: [[1, "Alice"], [2, "Bob"]],
        row_count: 2
      }

      tsv = Result.to_tsv(result)

      assert tsv == "id\tname\n1\tAlice\n2\tBob"
    end

    test "handles single column" do
      result = %Result{
        columns: [%{name: "count", type: :integer}],
        rows: [[42]],
        row_count: 1
      }

      tsv = Result.to_tsv(result)

      assert tsv == "count\n42"
    end

    test "handles empty result" do
      result = %Result{columns: [], rows: [], row_count: 0}
      tsv = Result.to_tsv(result)

      assert tsv == "\n"
    end
  end
end
