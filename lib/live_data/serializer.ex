defmodule LiveData.Serializer do
  @moduledoc false

  @json_patch_remove 0
  @json_patch_add 1
  @json_patch_replace 2
  @json_patch_test 3
  @json_patch_move 4
  @json_patch_copy 5

  def compress(patch) when is_list(patch) do
    Enum.flat_map(patch, &compress/1)
  end

  def compress(%{op: op, path: path, value: value}) do
    [operation_to_integer(op), path, value]
  end

  def compress(%{op: op, path: path, from: from}) do
    [operation_to_integer(op), path, from]
  end

  def compress(%{op: op, path: path}) do
    [operation_to_integer(op), path]
  end

  def decompress([]), do: []

  def decompress([@json_patch_remove = op, path | tail]) do
    [%{op: operation_to_string(op), path: path}] ++ decompress(tail)
  end

  def decompress([op, path, from | tail]) when op in [@json_patch_copy, @json_patch_move] do
    [%{op: operation_to_string(op), path: path, from: from}] ++ decompress(tail)
  end

  def decompress([op, path, value | tail])
      when op in [@json_patch_add, @json_patch_replace, @json_patch_test] do
    [%{op: operation_to_string(op), path: path, value: value}] ++ decompress(tail)
  end

  defp operation_to_string(@json_patch_add), do: "add"
  defp operation_to_string(@json_patch_replace), do: "replace"
  defp operation_to_string(@json_patch_test), do: "test"
  defp operation_to_string(@json_patch_move), do: "move"
  defp operation_to_string(@json_patch_copy), do: "copy"
  defp operation_to_string(@json_patch_remove), do: "remove"

  defp operation_to_integer("add"), do: @json_patch_add
  defp operation_to_integer("replace"), do: @json_patch_replace
  defp operation_to_integer("test"), do: @json_patch_test
  defp operation_to_integer("move"), do: @json_patch_move
  defp operation_to_integer("copy"), do: @json_patch_copy
  defp operation_to_integer("remove"), do: @json_patch_remove
end
