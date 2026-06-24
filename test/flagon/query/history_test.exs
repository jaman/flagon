defmodule Flagon.Query.HistoryTest do
  use ExUnit.Case, async: false

  alias Flagon.Query.History

  defp result(time \\ 5, rows \\ 3) do
    %Flagon.Query.Result{columns: [], rows: [], row_count: rows, execution_time_ms: time}
  end

  setup context do
    if tmp = context[:tmp_dir] do
      prev = Application.get_env(:flagon, :config_dir)
      Application.put_env(:flagon, :config_dir, tmp)
      on_exit(fn ->
        if prev, do: Application.put_env(:flagon, :config_dir, prev), else: Application.delete_env(:flagon, :config_dir)
      end)
    end

    History.clear()
    :ok
  end

  @tag :tmp_dir
  test "add/3 then list/0 returns the entry most-recent first" do
    History.add("select 1", result(), "A/RDB")
    History.add("select 2", result(), "A/RDB")

    entries = History.list()
    assert [%{query: "select 2"}, %{query: "select 1"}] = entries
    assert Enum.all?(entries, &(&1.connection == "A/RDB"))
  end

  @tag :tmp_dir
  test "get/1 fetches a stored entry by id and returns nil for unknown" do
    History.add("select 1", result(7, 9), "B/HDB")
    [entry] = History.list()

    assert ^entry = History.get(entry.id)
    assert entry.execution_time_ms == 7
    assert entry.row_count == 9
    assert History.get(999_999) == nil
  end

  @tag :tmp_dir
  test "clear/0 empties the history" do
    History.add("q", result(), "C")
    History.clear()
    assert History.list() == []
  end

  @tag :tmp_dir
  test "writes a Cachex snapshot under the config dir on add", %{tmp_dir: tmp} do
    History.add("q", result(), "C")
    History.list()
    assert File.exists?(Path.join(tmp, "history.cachex"))
  end
end
