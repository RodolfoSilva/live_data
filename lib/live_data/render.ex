defmodule LiveData.Render do
  @moduledoc false

  def render(view, assigns) do
    view
    |> apply(:render, [assigns])
    |> encode_to_map()
  end

  def diff(old, new) do
    Jsonpatch.diff(old, new)
    |> LiveData.Serializer.compress()
  end

  defp encode_to_map(screen) when is_struct(screen) do
    screen
    |> Map.from_struct()
    |> encode_to_map()
  end

  defp encode_to_map(value) when is_map(value) do
    for {k, v} <- value, !is_nil(v), into: %{}, do: {to_string(k), encode_to_map(v)}
  end

  defp encode_to_map(value) when is_list(value) do
    for v <- value, not is_nil(v), do: encode_to_map(v)
  end

  defp encode_to_map(value), do: value
end
