defmodule Flagon.ConfigDiscoveryTest do
  use ExUnit.Case, async: false

  setup %{tmp_dir: tmp} do
    prev = Application.get_env(:flagon, :config_dir)
    Application.put_env(:flagon, :config_dir, tmp)
    on_exit(fn ->
      if prev, do: Application.put_env(:flagon, :config_dir, prev), else: Application.delete_env(:flagon, :config_dir)
    end)

    :ok
  end

  @tag :tmp_dir
  test "auto-discovers servers.txt in the config dir", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "servers.txt"), "PROD/DDRM/DDRMFX@host1:9123\n")

    config = Flagon.Config.load([])
    assert Enum.any?(config.connections, &(&1.name == "DDRMFX" and &1.folder == "PROD/DDRM"))
  end

  @tag :tmp_dir
  test "auto-discovers servers.json and prefers it over servers.txt", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "servers.txt"), "A/FROMTXT@h:1\n")
    File.write!(Path.join(tmp, "servers.json"), ~s([{"host":"h","label":"FROMJSON","port":1,"tags":"A","user":"","password":"","useTLS":false}]))

    config = Flagon.Config.load([])
    names = Enum.map(config.connections, & &1.name)
    assert "FROMJSON" in names
    refute "FROMTXT" in names
  end

  @tag :tmp_dir
  test "an explicit :servers option overrides auto-discovery", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "servers.txt"), "A/DISCOVERED@h:1\n")
    explicit = Path.join(tmp, "explicit.txt")
    File.write!(explicit, "B/EXPLICIT@h:2\n")

    config = Flagon.Config.load(servers: explicit)
    names = Enum.map(config.connections, & &1.name)
    assert "EXPLICIT" in names
    refute "DISCOVERED" in names
  end

  @tag :tmp_dir
  test "a relative server_list path resolves against the config dir", %{tmp_dir: tmp} do
    File.write!(Path.join(tmp, "my_servers.txt"), "C/REL@h:3\n")

    assert [conn] = Flagon.Config.load_server_list("my_servers.txt")
    assert conn.name == "REL"
  end
end
