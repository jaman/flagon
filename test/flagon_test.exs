defmodule FlagonTest do
  use ExUnit.Case, async: true

  test "config defaults" do
    config = Flagon.Config.load([])
    assert config.page_size == 1000
    assert config.theme == "dracula"
  end
end
