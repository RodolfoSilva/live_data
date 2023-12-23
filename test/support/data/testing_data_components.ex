defmodule LiveData.Test.TestingComponent do
  use LiveData

  def mount(_params, socket) do
    {:ok, socket}
  end

  def render(assigns) do
    %{
      hello: assigns.name
    }
  end

  def handle_info(:increment, socket) do
    socket = assign(socket, :counter, socket.assigns.counter + 1)
    {:ok, socket}
  end

  def handle_event("increment", socket) do
    socket = assign(socket, :counter, socket.assigns.counter + 1)
    {:ok, socket}
  end
end

defmodule LiveData.Test.TestingDataComponents do
  use LiveData

  def mount(_params, socket) do
    socket = assign(socket, :counter, 0)

    {:ok, socket}
  end

  def render(assigns) do
    [
      %{
        counter: assigns[:counter],
        welcome:
          live_component(%{
            module: LiveData.Test.TestingComponent,
            id: "hello",
            name: "World"
          })
      },
      %{
        counter: assigns[:counter],
        welcome:
          live_component(%{
            module: LiveData.Test.TestingComponent,
            id: "hello",
            name: "Elixir"
          })
      }
    ]
  end
end
