defmodule LiveData.Test.Apply do
  @moduledoc false

  # Elixir utility for rendering out ops to a final data structure.
  #
  # Used by tests.

  defstruct rendered: %{}, flash: %{}, events: []

  def new do
    %__MODULE__{}
  end

  def apply(ops, state) do
    %{"r" => rendered} =
      ops
      |> LiveData.Serializer.decompress()
      |> Jsonpatch.apply_patch!(%{"r" => state.rendered})

    %{state | rendered: rendered, events: []}
  end
end
