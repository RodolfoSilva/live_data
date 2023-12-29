defmodule LiveData.Test.TestingData do
  use LiveData

  def mount(_params, socket) do
    socket =
      assign(socket, :counter, 0)
      |> assign_async(:lazy_counter, fn -> {:ok, %{lazy_counter: 3}} end)

    {:ok, socket}
  end

  def render(assigns) do
    %{
      counter: assigns[:counter],
      lazy_counter:
        async_result(assigns[:lazy_counter],
          ok: fn result -> result end,
          loading: fn -> "Loading..." end,
          failed: fn result -> "Failed: #{inspect(result)}" end
        )
    }
  end

  def handle_info(:increment, socket) do
    {:ok,
     socket
     |> put_flash(:info, "Incremented!")
     |> push_event("chart", %{})
     |> assign(:counter, socket.assigns.counter + 1)}
  end

  def handle_event("increment", _params, socket) do
    {:ok,
     socket
     |> assign(:counter, socket.assigns.counter + 1)}
  end
end
