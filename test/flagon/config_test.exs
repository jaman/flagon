defmodule Flagon.ConfigTest do
  use ExUnit.Case, async: true

  @tmp_dir System.tmp_dir!()

  describe "load/1" do
    test "returns defaults for standard keys" do
      config = Flagon.Config.load([])
      assert config.page_size == 1000
      assert config.query_timeout_ms == 30_000
      assert config.theme == "dracula"
      assert is_list(config.connections)
    end

    test "CLI opts override defaults" do
      config = Flagon.Config.load(page_size: 500, theme: "nord")
      assert config.page_size == 500
      assert config.theme == "nord"
    end
  end

  describe "parse_connection_string/1" do
    test "parses KDB connection string" do
      assert {:ok, conn} = Flagon.Config.parse_connection_string("kdb://localhost:5001")
      assert conn.type == :kdb
      assert conn.host == "localhost"
      assert conn.port == 5001
    end

    test "parses KDB connection with credentials" do
      assert {:ok, conn} = Flagon.Config.parse_connection_string("kdb://user:pass@myhost:5010")
      assert conn.type == :kdb
      assert conn.host == "myhost"
      assert conn.port == 5010
      assert conn.username == "user"
      assert conn.password == "pass"
    end

    test "parses PostgreSQL connection string" do
      dsn = "postgres://user:pass@host:5432/db"
      assert {:ok, conn} = Flagon.Config.parse_connection_string(dsn)
      assert conn.type == :postgres
      assert conn.dsn == dsn
    end

    test "parses DuckDB connection string" do
      assert {:ok, conn} = Flagon.Config.parse_connection_string("duckdb:///data/my.duckdb")
      assert conn.type == :duckdb
      assert conn.path == "/data/my.duckdb"
    end

    test "returns error for unknown format" do
      assert {:error, _} = Flagon.Config.parse_connection_string("unknown://foo")
    end
  end

  describe "Toml loader" do
    test "parses TOML config" do
      path = Path.join(@tmp_dir, "flagon_test_config.toml")

      File.write!(path, """
      [defaults]
      page_size = 2000
      theme = "nord"

      [[connections]]
      name = "test-kdb"
      type = "kdb"
      host = "localhost"
      port = 5001
      """)

      assert {:ok, config} = Flagon.Config.Toml.load(path)
      assert config.page_size == 2000
      assert config.theme == "nord"
      assert [conn] = config.connections
      assert conn.name == "test-kdb"
      assert conn.type == "kdb"
      assert conn.host == "localhost"
      assert conn.port == 5001

      File.rm!(path)
    end
  end

  describe "Exs loader" do
    test "evaluates .exs config" do
      path = Path.join(@tmp_dir, "flagon_test_config.exs")

      File.write!(path, """
      %{
        page_size: 3000,
        connections: [
          %{name: "local", type: :kdb, host: "127.0.0.1", port: 5001}
        ]
      }
      """)

      assert {:ok, config} = Flagon.Config.Exs.load(path)
      assert config.page_size == 3000
      assert [conn] = config.connections
      assert conn.name == "local"
      assert conn.type == :kdb

      File.rm!(path)
    end
  end
end
