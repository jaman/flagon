defmodule Flagon.App.QueryTextTest do
  use ExUnit.Case, async: true

  alias Flagon.App.QueryText

  @lines ["select 1", "select 2 from t", "where a>1"]

  test "extract_selected_text/2 returns a single-line slice" do
    assert QueryText.extract_selected_text(@lines, {0, 0, 0, 6}) == "select"
  end

  test "extract_selected_text/2 spans multiple lines" do
    assert QueryText.extract_selected_text(@lines, {0, 7, 1, 8}) == "1\nselect 2"
  end

  test "extract_selected_text/2 normalizes a backwards selection" do
    assert QueryText.extract_selected_text(@lines, {0, 6, 0, 0}) == "select"
  end

  test "extract_selected_text/2 includes whole middle lines" do
    assert QueryText.extract_selected_text(@lines, {0, 0, 2, 5}) == "select 1\nselect 2 from t\nwhere"
  end
end
