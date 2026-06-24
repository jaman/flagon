defmodule Flagon.Config.ServerListTest do
  use ExUnit.Case, async: true

  alias Flagon.Config.ServerList

  describe "parse_text/1" do
    test "parses a folder path, leaf name, host and port" do
      assert [conn] = ServerList.parse_text("PROD/DDRM/DDRMFX@nj1upxtp006.fxcorp:9123")
      assert conn.folder == "PROD/DDRM"
      assert conn.name == "DDRMFX"
      assert conn.host == "nj1upxtp006.fxcorp"
      assert conn.port == 9123
      assert conn.type == :kdb
    end

    test "parses trailing user and password" do
      line = "PROD/ARM/RED/RDB--tp-nj1cfdedge-0403-23.fxcorp:11202@204.8.241.101:11202:rdb:secret"
      assert [conn] = ServerList.parse_text(line)
      assert conn.folder == "PROD/ARM/RED"
      assert conn.name == "RDB--tp-nj1cfdedge-0403-23.fxcorp:11202"
      assert conn.host == "204.8.241.101"
      assert conn.port == 11202
      assert conn.username == "rdb"
      assert conn.password == "secret"
    end

    test "parses a root server with no folder" do
      assert [conn] = ServerList.parse_text("--LocalHost:5000@localhost:5000")
      assert conn.folder == ""
      assert conn.name == "--LocalHost:5000"
      assert conn.host == "localhost"
      assert conn.port == 5000
    end

    test "skips blank and malformed lines lacking an @" do
      text = """
      bash-5.1$ cat qStudio-Server-LIst.txt

      PROD/DDRM/DDRMFX@nj1upxtp006.fxcorp:9123
      """

      assert [conn] = ServerList.parse_text(text)
      assert conn.name == "DDRMFX"
    end
  end

  describe "parse_json/1" do
    test "maps tags to folder, label to name, and qStudio fields" do
      json = """
      [
        {"host": "h1", "label": "RDB", "password": "pw", "port": 11202,
         "tags": "PROD/ARM/RED", "uniqLabel": "PROD/ARM/RED,RDB",
         "useCustomizedAuth": false, "useTLS": true, "user": "rdb"}
      ]
      """

      assert [conn] = ServerList.parse_json(json)
      assert conn.folder == "PROD/ARM/RED"
      assert conn.name == "RDB"
      assert conn.host == "h1"
      assert conn.port == 11202
      assert conn.username == "rdb"
      assert conn.password == "pw"
      assert conn.tls == true
      assert conn.type == :kdb
    end

    test "treats empty tags as a root folder" do
      json = ~s([{"host": "localhost", "label": "--LocalHost:5000", "port": 5000, "tags": "", "user": "", "password": "", "useTLS": false}])
      assert [conn] = ServerList.parse_json(json)
      assert conn.folder == ""
      assert conn.name == "--LocalHost:5000"
    end
  end

  describe "round-trips" do
    test "to_text/1 is the inverse of parse_text/1" do
      lines = [
        "--LocalHost:5000@localhost:5000",
        "PROD/DDRM/DDRMFX@nj1upxtp006.fxcorp:9123",
        "PROD/ARM/RED/RDB--x:11202@204.8.241.101:11202:rdb:secret"
      ]

      text = Enum.join(lines, "\n")
      assert ServerList.parse_text(ServerList.to_text(ServerList.parse_text(text))) == ServerList.parse_text(text)
      assert ServerList.to_text(ServerList.parse_text(text)) == text
    end

    test "to_json/1 round-trips through parse_json/1" do
      conns = [
        %{folder: "PROD/ARM/RED", name: "RDB", type: :kdb, host: "h1", port: 11202, username: "rdb", password: "pw", tls: true},
        %{folder: "", name: "local", type: :kdb, host: "localhost", port: 5000, username: nil, password: nil, tls: false}
      ]

      assert ServerList.parse_json(ServerList.to_json(conns)) |> Enum.map(& &1.name) == ["RDB", "local"]
      reparsed = ServerList.parse_json(ServerList.to_json(conns))
      assert Enum.at(reparsed, 0).folder == "PROD/ARM/RED"
      assert Enum.at(reparsed, 0).tls == true
    end
  end

  describe "real fixture files" do
    test "parse the repo's example servers_list.txt and server_list.json without crashing" do
      txt_path = Path.join(File.cwd!(), "servers_list.txt")
      json_path = Path.join(File.cwd!(), "server_list.json")

      if File.exists?(txt_path) do
        conns = txt_path |> File.read!() |> ServerList.parse_text()
        assert length(conns) > 100
        assert Enum.all?(conns, &(&1.type == :kdb and is_integer(&1.port)))
      end

      if File.exists?(json_path) do
        conns = json_path |> File.read!() |> ServerList.parse_json()
        assert length(conns) > 100
        assert Enum.all?(conns, &is_binary(&1.folder))
      end
    end
  end
end
