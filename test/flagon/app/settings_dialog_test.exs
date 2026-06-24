defmodule Flagon.App.SettingsDialogTest do
  use ExUnit.Case, async: true

  test "theme_options/0 includes the Config default theme so it is selectable" do
    names = Enum.map(Flagon.App.SettingsDialog.theme_options(), &elem(&1, 0))
    assert "dracula" in names
  end

  test "theme_options/0 match the themes Drafter actually supports" do
    expected = Drafter.Theme.available_themes() |> Map.keys() |> Enum.sort()
    names = Flagon.App.SettingsDialog.theme_options() |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    assert names == expected
  end
end
