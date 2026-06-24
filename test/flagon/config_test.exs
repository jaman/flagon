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

  describe "qualified_name/1" do
    test "joins folder and name with a slash" do
      assert Flagon.Config.qualified_name(%{folder: "PROD/ARM/RED", name: "RDB"}) == "PROD/ARM/RED/RDB"
    end

    test "uses the bare name when there is no folder" do
      assert Flagon.Config.qualified_name(%{folder: "", name: "local"}) == "local"
      assert Flagon.Config.qualified_name(%{folder: nil, name: "local"}) == "local"
      assert Flagon.Config.qualified_name(%{name: "local"}) == "local"
    end
  end

  describe "server list loading" do
    @tag :tmp_dir
    test "load_server_list/1 parses a .txt file as a hierarchical server list", %{tmp_dir: tmp} do
      path = Path.join(tmp, "servers.txt")
      File.write!(path, "PROD/DDRM/DDRMFX@host1:9123\n--Local@localhost:5000\n")

      assert [a, b] = Flagon.Config.load_server_list(path)
      assert a.folder == "PROD/DDRM"
      assert a.name == "DDRMFX"
      assert a.type == :kdb
      assert b.folder == ""
    end

    @tag :tmp_dir
    test "load_server_list/1 parses a .json file by extension", %{tmp_dir: tmp} do
      path = Path.join(tmp, "servers.json")
      File.write!(path, ~s([{"host":"h","label":"RDB","port":1,"tags":"A/B","user":"","password":"","useTLS":false}]))

      assert [conn] = Flagon.Config.load_server_list(path)
      assert conn.folder == "A/B"
      assert conn.name == "RDB"
    end

    @tag :tmp_dir
    test "load/1 merges connections from a :servers option", %{tmp_dir: tmp} do
      path = Path.join(tmp, "servers.txt")
      File.write!(path, "PROD/DDRM/DDRMFX@host1:9123\n")

      config = Flagon.Config.load(servers: path)
      assert Enum.any?(config.connections, fn c -> c.name == "DDRMFX" and c.folder == "PROD/DDRM" end)
    end
  end

  describe "Toml encode/1" do
    @tag :tmp_dir
    test "round-trips defaults and connections through the loader", %{tmp_dir: tmp} do
      config = %{
        page_size: 2000,
        query_timeout_ms: 45_000,
        theme: "nord",
        connections: [
          %{name: "kdb_prod", type: :kdb, host: "k.example.com", port: 5010, username: "u", password: "p"},
          %{name: "pg", type: :postgres, dsn: "postgres://h/db"},
          %{name: "analytics", type: :duckdb, path: "/data/a.duckdb"}
        ]
      }

      path = Path.join(tmp, "config.toml")
      File.write!(path, Flagon.Config.Toml.encode(config))

      assert {:ok, loaded} = Flagon.Config.Toml.load(path)
      assert loaded.page_size == 2000
      assert loaded.query_timeout_ms == 45_000
      assert loaded.theme == "nord"
      assert [kdb, pg, duck] = loaded.connections
      assert kdb.name == "kdb_prod"
      assert kdb.type == "kdb"
      assert kdb.host == "k.example.com"
      assert kdb.port == 5010
      assert kdb.username == "u"
      assert kdb.password == "p"
      assert pg.type == "postgres"
      assert pg.dsn == "postgres://h/db"
      assert duck.type == "duckdb"
      assert duck.path == "/data/a.duckdb"
    end

    @tag :tmp_dir
    test "preserves folder hierarchy and tls flag through a round-trip", %{tmp_dir: tmp} do
      config = %{
        page_size: 1000,
        query_timeout_ms: 30_000,
        theme: "dracula",
        connections: [%{name: "RDB", type: :kdb, folder: "PROD/ARM/RED", host: "h", port: 11202, tls: true}]
      }

      path = Path.join(tmp, "config.toml")
      File.write!(path, Flagon.Config.Toml.encode(config))

      assert {:ok, loaded} = Flagon.Config.Toml.load(path)
      assert [conn] = loaded.connections
      assert conn.folder == "PROD/ARM/RED"
      assert conn.tls == true
    end

    @tag :tmp_dir
    test "omits nil connection fields", %{tmp_dir: tmp} do
      config = %{
        page_size: 1000,
        query_timeout_ms: 30_000,
        theme: "dracula",
        connections: [%{name: "k", type: :kdb, host: "h", port: 5001, username: nil, password: nil, dsn: nil, path: nil}]
      }

      path = Path.join(tmp, "config.toml")
      File.write!(path, Flagon.Config.Toml.encode(config))

      assert {:ok, loaded} = Flagon.Config.Toml.load(path)
      assert [conn] = loaded.connections
      refute Map.has_key?(conn, :username)
      refute Map.has_key?(conn, :password)
      refute Map.has_key?(conn, :dsn)
      refute Map.has_key?(conn, :path)
    end

    @tag :tmp_dir
    test "escapes strings containing quotes and backslashes", %{tmp_dir: tmp} do
      config = %{
        page_size: 1000,
        query_timeout_ms: 30_000,
        theme: "dracula",
        connections: [%{name: ~S(weird"name\x), type: :duckdb, path: ~S(C:\data\"q".db)}]
      }

      path = Path.join(tmp, "config.toml")
      File.write!(path, Flagon.Config.Toml.encode(config))

      assert {:ok, loaded} = Flagon.Config.Toml.load(path)
      assert [conn] = loaded.connections
      assert conn.name == ~S(weird"name\x)
      assert conn.path == ~S(C:\data\"q".db)
    end
  end

  describe "save/2" do
    @tag :tmp_dir
    test "persists config as TOML and reloads identically", %{tmp_dir: tmp} do
      config = %{
        page_size: 750,
        query_timeout_ms: 30_000,
        theme: "dracula",
        connections: [%{name: "local", type: :kdb, host: "127.0.0.1", port: 5001}]
      }

      assert :ok = Flagon.Config.save(config, dir: tmp)
      assert File.exists?(Path.join(tmp, "config.toml"))

      assert {:ok, loaded} = Flagon.Config.Toml.load(Path.join(tmp, "config.toml"))
      assert loaded.page_size == 750
      assert [conn] = loaded.connections
      assert conn.name == "local"
    end

    @tag :tmp_dir
    test "writes .exs when an .exs config already exists", %{tmp_dir: tmp} do
      File.write!(Path.join(tmp, "config.exs"), "%{page_size: 1}")

      config = %{page_size: 999, query_timeout_ms: 30_000, theme: "dracula", connections: []}
      assert :ok = Flagon.Config.save(config, dir: tmp)

      refute File.exists?(Path.join(tmp, "config.toml"))
      assert {:ok, loaded} = Flagon.Config.Exs.load(Path.join(tmp, "config.exs"))
      assert loaded.page_size == 999
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
