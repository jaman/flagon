defmodule Flagon.Query.Result do
  @moduledoc """
  Normalized query result across all database backends.
  """

  defstruct columns: [],
            rows: [],
            row_count: 0,
            execution_time_ms: 0,
            truncated?: false,
            error: nil

  @type column :: %{name: String.t(), type: atom()}

  @type t :: %__MODULE__{
          columns: [column()],
          rows: [[term()]],
          row_count: non_neg_integer(),
          execution_time_ms: non_neg_integer(),
          truncated?: boolean(),
          error: String.t() | nil
        }

  @spec from_maps([map()], non_neg_integer()) :: t()
  def from_maps([], elapsed) do
    %__MODULE__{execution_time_ms: elapsed}
  end

  def from_maps(rows, elapsed) when is_list(rows) do
    column_names = rows |> List.first() |> Map.keys() |> Enum.sort()

    columns = Enum.map(column_names, fn name ->
      type = rows |> List.first() |> Map.get(name) |> infer_type()
      %{name: to_string(name), type: type}
    end)

    data = Enum.map(rows, fn row ->
      Enum.map(column_names, fn col -> Map.get(row, col) end)
    end)

    %__MODULE__{
      columns: columns,
      rows: data,
      row_count: length(data),
      execution_time_ms: elapsed
    }
  end

  @spec from_scalar(term(), non_neg_integer()) :: t()
  def from_scalar(value, elapsed) do
    %__MODULE__{
      columns: [%{name: "result", type: infer_type(value)}],
      rows: [[value]],
      row_count: 1,
      execution_time_ms: elapsed
    }
  end

  @spec from_ecto(%{columns: [String.t()], rows: [[term()]], num_rows: non_neg_integer()}, non_neg_integer()) :: t()
  def from_ecto(%{columns: col_names, rows: rows, num_rows: num_rows}, elapsed) do
    columns = Enum.map(col_names, fn name ->
      type =
        case rows do
          [first_row | _] ->
            idx = Enum.find_index(col_names, &(&1 == name))
            Enum.at(first_row, idx) |> infer_type()

          [] ->
            :unknown
        end

      %{name: name, type: type}
    end)

    %__MODULE__{
      columns: columns,
      rows: rows,
      row_count: num_rows,
      execution_time_ms: elapsed
    }
  end

  @spec page(t(), non_neg_integer(), non_neg_integer()) :: {[[term()]], non_neg_integer()}
  def page(%__MODULE__{rows: rows, row_count: row_count}, page_number, page_size) do
    total_pages = max(1, ceil(row_count / page_size))
    clamped_page = max(1, min(page_number, total_pages))
    offset = (clamped_page - 1) * page_size

    paged_rows =
      rows
      |> Enum.drop(offset)
      |> Enum.take(page_size)

    {paged_rows, total_pages}
  end

  @spec to_data_table_format(t(), non_neg_integer(), non_neg_integer()) ::
          {[map()], [map()], non_neg_integer()}
  def to_data_table_format(%__MODULE__{} = result, page_number \\ 1, page_size \\ 1000) do
    {paged_rows, total_pages} = page(result, page_number, page_size)

    col_keys = Enum.map(result.columns, fn col ->
      col.name |> String.replace(~r/[^\w]/, "_") |> String.to_atom()
    end)

    dt_columns = Enum.zip(result.columns, col_keys) |> Enum.map(fn {col, key} ->
      %{key: key, label: col.name, width: :auto, sortable: true}
    end)

    dt_data = Enum.map(paged_rows, fn row ->
      Enum.zip(col_keys, row) |> Map.new()
    end)

    {dt_columns, dt_data, total_pages}
  end

  @spec to_tsv(t()) :: String.t()
  def to_tsv(%__MODULE__{columns: columns, rows: rows}) do
    header = Enum.map_join(columns, "\t", & &1.name)

    data =
      Enum.map_join(rows, "\n", fn row ->
        Enum.map_join(row, "\t", &to_string/1)
      end)

    "#{header}\n#{data}"
  end

  defp infer_type(nil), do: :unknown
  defp infer_type(v) when is_integer(v), do: :integer
  defp infer_type(v) when is_float(v), do: :float
  defp infer_type(v) when is_boolean(v), do: :boolean
  defp infer_type(v) when is_binary(v), do: :string
  defp infer_type(%DateTime{}), do: :datetime
  defp infer_type(%Date{}), do: :date
  defp infer_type(%Time{}), do: :time
  defp infer_type(v) when is_atom(v), do: :atom
  defp infer_type(v) when is_list(v), do: :list
  defp infer_type(v) when is_map(v), do: :map
  defp infer_type(_), do: :unknown
end
