defmodule LiveData.Test do
  alias LiveData.Test.ClientProxy

  defmacro __using__(_opts) do
    quote do
      import __MODULE__, only: [data: 1]
    end
  end

  def live_data(data_module, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, LiveData.Test.DummyEndpoint)

    start_proxy(%{
      module: data_module,
      endpoint: endpoint
    })
  end

  def client_event(view, event, payload \\ %{}) do
    GenServer.call(view.proxy, {:push_client_event, {event, payload}})
  end

  def render(view) do
    GenServer.call(view.proxy, :render)
  end

  def act_and_render(view) do
    Process.sleep(1)
    GenServer.call(view.proxy, :render)
  end

  def render_client_event(view, event, payload \\ %{}) do
    client_event(view, event, payload)
    render(view)
  end

  def render_server_event(view, event) do
    send(view.pid, event)
    render(view)
  end

  defp start_proxy(%{} = opts) do
    ref = make_ref()

    opts =
      Map.merge(opts, %{
        caller: {self(), ref},
        test_supervisor: fetch_test_supervisor!()
      })

    case ClientProxy.start_link(opts) do
      {:ok, _} ->
        receive do
          {^ref, {:ok, view, data}} -> {:ok, view, data}
        end
    end
  end

  defp fetch_test_supervisor!() do
    case ExUnit.fetch_test_supervisor() do
      {:ok, sup} -> sup
      :error -> raise ArgumentError, "LiveData helpers can only be invoked from the test process"
    end
  end
end
