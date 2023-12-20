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
  Annotates the changes with the event to be pushed.

  Events are dispatched on the JavaScript side only after
  the current patch is invoked. Therefore, if the LiveView
  redirects, the events won't be invoked.
  """
  def push_event(%Socket{} = socket, event, %{} = payload) do
    update_in(socket.private.live_temp[:push_events], &[[event, payload] | &1 || []])
  end

  @doc """
  Returns the push events in the socket.
  """
  def get_push_events(%Socket{} = socket) do
    Enum.reverse(socket.private.live_temp[:push_events] || [])
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
