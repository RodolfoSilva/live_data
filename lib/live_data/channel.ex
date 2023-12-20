defmodule LiveData.Channel do
  @moduledoc false

  @prefix :live_data

  use GenServer, restart: :temporary

  require Logger

  alias Phoenix.Socket.Message
  alias LiveData.Socket

  def ping(pid) do
    GenServer.call(pid, {@prefix, :ping})
  end

  defstruct socket: nil,
            view: nil,
            topic: nil,
            serializer: nil,
            count: -1,
            rendered: %{}

  def start_link({endpoint, from}) do
    if LiveData.debug_prints?(), do: IO.inspect({endpoint, from})
    hibernate_after = endpoint.config(:live_data)[:hibernate_after] || 15000
    opts = [hibernate_after: hibernate_after]
    GenServer.start_link(__MODULE__, from, opts)
  end

  @impl true
  def init({pid, _ref}) do
    {:ok, Process.monitor(pid)}
  end

  @impl true
  def handle_call({@prefix, :ping}, _from, state) do
    {:reply, :ok, state}
  end

  @impl true
  def handle_info({Phoenix.Channel, params, from, phx_socket}, ref) do
    if LiveData.debug_prints?(), do: IO.inspect({params, from, phx_socket})
    Process.demonitor(ref)

    mount(params, from, phx_socket)
  end

  def handle_info(
        {:DOWN, _ref, _typ, transport_pid, _reason},
        %{socket: %{transport_pid: transport_pid}} = state
      ) do
    {:stop, {:shutdown, :closed}, state}
  end

  def handle_info(%Message{event: "e", payload: %{"d" => data}}, state) do
    {:ok, socket} = state.view.handle_event(data, state.socket)
    state = %{state | socket: socket}
    state = render_view(state)
    {:noreply, state}
  end

  def handle_info(message, state) do
    {:ok, socket} = state.view.handle_info(message, state.socket)
    state = %{state | socket: socket}
    state = render_view(state)
    {:noreply, state}
  end

  defp call_handler({module, function}, params) do
    apply(module, function, [params])
  end

  defp call_handler(fun, params) when is_function(fun, 1) do
    fun.(params)
  end

  defp mount(params, from, phx_socket) do
    handler = phx_socket.assigns.live_data_handler

    case call_handler(handler, params) do
      {view_module, view_opts, %{extra: extra}} ->
        mount_view(view_module, view_opts, extra, params, from, phx_socket)

      nil ->
        GenServer.reply(from, {:error, %{reason: "no_route"}})
        {:stop, :shutdown, :no_state}
    end
  end

  defp mount_view(view_module, _view_opts, extra, params, from, phx_socket) do
    %Phoenix.Socket{
      endpoint: endpoint,
      transport_pid: transport_pid
      # handler: router
    } = phx_socket

    Process.monitor(transport_pid)

    case params do
      %{"caller" => {pid, _}} when is_pid(pid) -> Process.put(:"$callers", [pid])
      _ -> Process.put(:"$callers", [transport_pid])
    end

    lifecycle = LiveData.Lifecycle.mount(view_module, Enum.reverse(extra[:on_mount] || []))

    socket = %Socket{
      endpoint: endpoint,
      transport_pid: transport_pid,
      private: %{
        lifecycle: lifecycle,
        live_temp: %{}
      }
    }

    state = %__MODULE__{
      socket: socket,
      view: view_module,
      topic: phx_socket.topic,
      serializer: phx_socket.serializer
    }

    state = maybe_call_data_view_mount!(state, params)

    if LiveData.debug_prints?(), do: IO.inspect(state)

    case state.socket.redirected do
      {:redirect, %{to: _to} = opts} ->
        state
        |> push_redirect(opts, from)
        |> stop_shutdown_redirect(:redirect, opts)

      _ ->
        :ok = GenServer.reply(from, {:ok, %{}})
        state = render_view(state)
        {:noreply, state}
    end
  end

  defp stop_shutdown_redirect(state, kind, opts) do
    send(state.socket.transport_pid, {:socket_close, self(), {kind, opts}})
    {:stop, {:shutdown, {kind, opts}}, state}
  end

  defp push_redirect(state, opts, nil = _ref) do
    push(state, "redirect", opts)
  end

  defp push_redirect(state, opts, ref) do
    reply(state, ref, :ok, %{redirect: opts})
    state
  end

  defp reply(state, ref, status, payload) do
    GenServer.reply(ref, {status, payload})
    state
  end

  defp after_render(%{socket: socket} = state) do
    state =
      LiveData.Utils.get_push_events(socket)
      |> Enum.reduce(state, fn [event, payload], state ->
        push(state, event, payload)
      end)

    %{state | socket: %Socket{socket | private: Map.put(socket.private, :live_temp, %{})}}
  end

  defp render_view(%{view: view, count: count, socket: socket} = state) do
    rendered = LiveData.Render.render(view, socket.assigns)
    patch = LiveData.Render.diff(%{"r" => state.rendered}, %{"r" => rendered})
    new_count = count + 1
    state = push(state, "o", %{"o" => patch, "c" => new_count})
    state = %{state | rendered: rendered, count: new_count}

    if LiveData.debug_prints?(),
      do: Logger.debug("Rendered: #{state.topic} \n  Patch: #{inspect(patch)}")

    after_render(state)
  end

  defp maybe_call_data_view_mount!(state, params) do
    session = %{}
    socket = state.socket
    %{exported?: exported?} = LiveData.Lifecycle.stage_info(socket, state.view, :mount, 2)

    safe_params = Map.get(params, "p", %{})

    socket =
      case LiveData.Lifecycle.mount(safe_params, session, socket) do
        {:cont, %Socket{} = socket} when exported? ->
          {:ok, socket} = state.view.mount(safe_params, socket)
          socket

        {_, %Socket{} = socket} ->
          socket
      end

    %{state | socket: socket}
  end

  defp push(state, event, payload) do
    message = %Message{topic: state.topic, event: event, payload: payload}
    send(state.socket.transport_pid, state.serializer.encode!(message))
    state
  end
end
