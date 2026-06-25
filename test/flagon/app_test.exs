defmodule Flagon.AppTest do
  use ExUnit.Case, async: false

  setup context do
    if tmp = context[:tmp_dir] do
      prev = Application.get_env(:flagon, :config_dir)
      Application.put_env(:flagon, :config_dir, tmp)

      on_exit(fn ->
        if prev,
          do: Application.put_env(:flagon, :config_dir, prev),
          else: Application.delete_env(:flagon, :config_dir)
      end)
    end

    :ok
  end

  defp base_state do
    %{
      config: %{page_size: 1000, query_timeout_ms: 30_000, theme: "dracula", connections: []},
      connections: [],
      conn_statuses: %{},
      query_target: nil,
      query_text: "old query",
      result: nil,
      result_tab: :history,
      page_size: 1000
    }
  end

  describe "handle_event/3 :history_result" do
    test "loads the selected query into the editor and switches to the result tab" do
      assert {:ok, new} =
               Flagon.App.handle_event(:history_result, {:use_query, "select 1"}, base_state())

      assert new.query_text == "select 1"
      assert new.result_tab == :result
    end
  end

  describe "handle_event/3 :run_query" do
    @tag :tmp_dir
    test "clears the previous result, marks executing, and records the executed query" do
      Flagon.Connection.Manager.load_connections([%{name: "k", type: :kdb, host: "h", port: 1}])

      state = %{
        Flagon.App.mount(%{})
        | query_target: "k",
          query_text: "select 1",
          result: %Flagon.Query.Result{row_count: 5}
      }

      assert {:ok, new} = Flagon.App.handle_event(:run_query, nil, state)
      assert new.result == nil
      assert new.executing? == true
      assert new.executed_query == "select 1"
    end
  end

  describe "handle_event/3 :connection_result" do
    @tag :tmp_dir
    test "persists connections to disk and updates state", %{tmp_dir: tmp} do
      conns = [%{name: "k", type: :kdb, host: "h", port: 5001}]

      assert {:ok, new} =
               Flagon.App.handle_event(:connection_result, {:updated, conns}, base_state())

      assert new.connections == conns
      assert new.config.connections == conns
      assert new.query_target == "k"
      assert Map.has_key?(new.conn_statuses, "k")

      assert {:ok, loaded} = Flagon.Config.Toml.load(Path.join(tmp, "config.toml"))
      assert [conn] = loaded.connections
      assert conn.name == "k"
    end

    @tag :tmp_dir
    test "drops query_target and status when its connection is removed" do
      state = %{base_state() | query_target: "old", conn_statuses: %{"old" => :connected}}
      conns = [%{name: "k", type: :kdb, host: "h", port: 5001}]

      assert {:ok, new} = Flagon.App.handle_event(:connection_result, {:updated, conns}, state)
      assert new.query_target == "k"
      refute Map.has_key?(new.conn_statuses, "old")
    end
  end

  describe "handle_event/3 :settings_result" do
    @tag :tmp_dir
    test "persists settings to disk and updates state", %{tmp_dir: tmp} do
      settings = %{page_size: 250, query_timeout_ms: 12_345, theme: "nord"}

      assert {:ok, new} =
               Flagon.App.handle_event(:settings_result, {:saved, settings}, base_state())

      assert new.page_size == 250
      assert new.config.theme == "nord"
      assert new.config.query_timeout_ms == 12_345

      assert {:ok, loaded} = Flagon.Config.Toml.load(Path.join(tmp, "config.toml"))
      assert loaded.theme == "nord"
      assert loaded.page_size == 250
    end
  end
end
