defmodule Flagon.App.QueryText do
  @spec extract(atom(), :all | :selection | :line) :: String.t()
  def extract(widget_id, mode) do
    case Drafter.get_widget_state(widget_id) do
      nil -> ""
      state -> extract_for_mode(state, mode)
    end
  end

  defp extract_for_mode(state, :all), do: Enum.join(state.lines, "\n")

  defp extract_for_mode(state, :line), do: Enum.at(state.lines, state.cursor_line, "")

  defp extract_for_mode(state, :selection) do
    case state.selection do
      nil -> extract_for_mode(state, :line)
      selection -> extract_selected_text(state.lines, selection)
    end
  end

  @spec extract_selected_text([String.t()], {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}) :: String.t()
  def extract_selected_text(lines, {start_line, start_col, end_line, end_col}) do
    {start_line, start_col, end_line, end_col} = normalize(start_line, start_col, end_line, end_col)

    cond do
      start_line == end_line ->
        lines
        |> Enum.at(start_line, "")
        |> String.slice(start_col, end_col - start_col)

      true ->
        first = lines |> Enum.at(start_line, "") |> String.slice(start_col..-1//1)
        last = lines |> Enum.at(end_line, "") |> String.slice(0, end_col)

        middle =
          if end_line - start_line > 1 do
            Enum.slice(lines, (start_line + 1)..(end_line - 1))
          else
            []
          end

        Enum.join([first] ++ middle ++ [last], "\n")
    end
  end

  defp normalize(start_line, start_col, end_line, end_col) when start_line > end_line do
    {end_line, end_col, start_line, start_col}
  end

  defp normalize(line, start_col, line, end_col) when start_col > end_col do
    {line, end_col, line, start_col}
  end

  defp normalize(start_line, start_col, end_line, end_col) do
    {start_line, start_col, end_line, end_col}
  end
end
