defmodule LiveData.Render do
  @moduledoc false

  def render(view, assigns) do
    {rendered, components} = __render__(view, assigns)
    {encode_to_map(rendered), components}
  end

  defp __render__(view, assigns) do
    view
    |> apply(:render, [assigns])
    |> render_components()
  end

  defp render_components(view) when is_list(view) do
    {list_render, components} =
      Enum.reduce(view, {[], []}, fn view, {acc_views, acc_components} ->
        {rendered, components} = render_components(view)

        {[rendered | acc_views], components ++ acc_components}
      end)

    {Enum.reverse(list_render), components}
  end

  defp render_components(view) when is_struct(view) do
    view
    |> Map.from_struct()
    |> render_components()
  end

  defp render_components(view) when is_map(view) do
    {views, components} =
      view
      |> Enum.reduce({%{}, []}, fn
        {k, %LiveData.Component{} = v}, {acc_map, acc_list} ->
          {rendered, components} = __render__(v.component, v.assigns)
          {Map.put(acc_map, k, rendered), [rendered | acc_list] ++ components}

        {k, v}, {acc_map, acc_list} ->
          {Map.put(acc_map, k, v), acc_list}
      end)

    {views, Enum.reverse(components)}
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
