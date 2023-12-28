defmodule LiveData.Utils do
  alias LiveData.Socket

  @valid_uri_schemes [
    "http:",
    "https:",
    "ftp:",
    "ftps:",
    "mailto:",
    "news:",
    "irc:",
    "gopher:",
    "nntp:",
    "feed:",
    "telnet:",
    "mms:",
    "rtsp:",
    "svn:",
    "tel:",
    "fax:",
    "xmpp:"
  ]

  def cid(%Socket{}), do: nil

  @doc """
  Assigns a value if it changed.
  """
  def assign(%Socket{} = socket, key, value) do
    case socket do
      %{assigns: %{^key => ^value}} -> socket
      %{} -> force_assign(socket, key, value)
    end
  end

  @doc """
  Assigns the given `key` with value from `fun` into `socket_or_assigns` if one does not yet exist.
  """
  def assign_new(%Socket{} = socket, key, fun) when is_function(fun, 1) do
    case socket do
      %{assigns: %{^key => _}} ->
        socket

      %{private: %{assign_new: {assigns, keys}}} ->
        # It is important to store the keys even if they are not in assigns
        # because maybe the controller doesn't have it but the view does.
        socket = put_in(socket.private.assign_new, {assigns, [key | keys]})

        LiveData.Utils.force_assign(
          socket,
          key,
          case assigns do
            %{^key => value} -> value
            %{} -> fun.(socket.assigns)
          end
        )

      %{assigns: assigns} ->
        LiveData.Utils.force_assign(socket, key, fun.(assigns))
    end
  end

  def assign_new(%Socket{} = socket, key, fun) when is_function(fun, 0) do
    case socket do
      %{assigns: %{^key => _}} ->
        socket

      %{private: %{assign_new: {assigns, keys}}} ->
        # It is important to store the keys even if they are not in assigns
        # because maybe the controller doesn't have it but the view does.
        socket = put_in(socket.private.assign_new, {assigns, [key | keys]})
        LiveData.Utils.force_assign(socket, key, Map.get_lazy(assigns, key, fun))

      %{} ->
        LiveData.Utils.force_assign(socket, key, fun.())
    end
  end

  @doc """
  Forces an assign on a socket.
  """
  def force_assign(%Socket{assigns: assigns} = socket, key, val) do
    %{socket | assigns: force_assign(assigns, assigns.__changed__, key, val)}
  end

  @doc """
  Forces an assign with the given changed map.
  """
  def force_assign(assigns, nil, key, val), do: Map.put(assigns, key, val)

  def force_assign(assigns, changed, key, val) do
    # If the current value is a map, we store it in changed so
    # we can perform nested change tracking. Also note the use
    # of put_new is important. We want to keep the original value
    # from assigns and not any intermediate ones that may appear.
    current_val = Map.get(assigns, key)
    changed_val = if is_map(current_val), do: current_val, else: true
    changed = Map.put_new(changed, key, changed_val)
    Map.put(%{assigns | __changed__: changed}, key, val)
  end

  @doc """
  Annotates the changes with the event to be pushed.

  Events are dispatched on the JavaScript side only after
  the current patch is invoked. Therefore, if the LiveView
  redirects, the events won't be invoked.
  """
  def push_event(%Socket{} = socket, event, %{} = payload) do
    update_in(socket.private.live_temp[:push_events], &[[event, payload] | &1 || []])
  end

  @doc """
  Returns the socket's flash messages.
  """
  def get_flash(%Socket{assigns: assigns}), do: assigns.flash
  def get_flash(%{} = flash, key), do: flash[key]

  @doc """
  Puts a new flash with the socket's flash messages.
  """
  def replace_flash(%Socket{} = socket, %{} = new_flash) do
    assign(socket, :flash, new_flash)
  end

  @doc """
  Clears the flash.
  """
  def clear_flash(%Socket{} = socket) do
    assign(socket, :flash, %{})
  end

  @doc """
  Clears the key from the flash.
  """
  def clear_flash(%Socket{} = socket, key) do
    key = flash_key(key)
    new_flash = Map.delete(socket.assigns[:flash] || %{}, key)

    socket = assign(socket, :flash, new_flash)
    update_in(socket.private.live_temp[:flash], &Map.delete(&1 || %{}, key))
  end

  @doc """
  Puts a flash message in the socket.
  """
  def put_flash(%Socket{assigns: assigns} = socket, key, msg) do
    key = flash_key(key)
    new_flash = Map.put(assigns[:flash] || %{}, key, msg)

    socket = assign(socket, :flash, new_flash)
    update_in(socket.private.live_temp[:flash], &Map.put(&1 || %{}, key, msg))
  end

  @doc """
  Returns a map of the flash messages which have changed.
  """
  def changed_flash(%Socket{} = socket) do
    socket.private.live_temp[:flash] || %{}
  end

  defp flash_key(binary) when is_binary(binary), do: binary
  defp flash_key(atom) when is_atom(atom), do: Atom.to_string(atom)

  @doc """
  Annotates the reply in the socket changes.
  """
  def put_reply(%Socket{} = socket, %{} = payload) do
    put_in(socket.private.live_temp[:push_reply], payload)
  end

  @doc """
  Returns the push events in the socket.
  """
  def get_push_events(%Socket{} = socket) do
    Enum.reverse(socket.private.live_temp[:push_events] || [])
  end

  @doc """
  Returns the reply in the socket.
  """
  def get_reply(%Socket{} = socket) do
    socket.private.live_temp[:push_reply]
  end

  def valid_destination!(%URI{} = uri, context) do
    valid_destination!(URI.to_string(uri), context)
  end

  def valid_destination!({:safe, to}, context) do
    {:safe, valid_string_destination!(IO.iodata_to_binary(to), context)}
  end

  def valid_destination!({other, to}, _context) when is_atom(other) do
    [Atom.to_string(other), ?:, to]
  end

  def valid_destination!(to, context) do
    valid_string_destination!(IO.iodata_to_binary(to), context)
  end

  for scheme <- @valid_uri_schemes do
    def valid_string_destination!(unquote(scheme) <> _ = string, _context), do: string
  end

  def valid_string_destination!(to, context) do
    if not match?("/" <> _, to) and String.contains?(to, ":") do
      raise ArgumentError, """
      unsupported scheme given to #{context}. In case you want to link to an
      unknown or unsafe scheme, such as javascript, use a tuple: {:javascript, rest}
      """
    else
      to
    end
  end
end
