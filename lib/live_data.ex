defmodule LiveData do
  @moduledoc """
  LiveData makes it easy to synchronize a JSON data structure from the server
  to a client. Changes to the data structure over time is streamed as minimal
  diffs.

  LiveData aims to provide a programming model similar to LiveView, but for
  arbitrary data structures instead of only HTML.

  You write a `render` function in your LiveData, which takes any assigns you
  have set as an argument. Within the `render` function you build the data
  structure you want synchronized to the client. As you update the `assigns`,
  the LiveData library will take care of calling your `render` function,
  calculating diffs, and synchronizing to the client.

  As with LiveView, your LiveData is just a normal process. The programming
  model should feel very familiar if you have ever used LiveView before.

  ## Live-cycle
  Unlike with LiveView, the lifecycle of a LiveData is not tied closely to
  any given HTTP request.

  In order to open a connection to a LiveData from the client, you would
  start out by making a connection to the LiveData socket endpoint.

  On the LiveData socket connection, the client can then connect to any
  number of LiveDatas.

  A LiveData ends when either:
   * The client closes the LiveData socket connection. This will cause all
     LiveDatas that live on that socket to close.
   * The client closes the individual LiveData. This will cause any other
     LiveDatas on the socket to remain open.
   * The LiveData crashes or disconnects from the server side.

  On a server-side crash or disconnect, it is up to the client to decide
  how to handle it. A common behaviour might be to reconnect.

  ## Keys
  Using keys are very important if you want the LiveData library to generate
  efficient diffs for you.

  Keys allow you to give the LiveData library a hint that it can identify a
  piece of data uniquely by a given identifier.

  As a rule of thumb, you should use a key whenever are looping over and
  generating output from something dynamic.

  ### Example
  Say you have the following LiveData which returns a list of users:

  ```elixir
  deft render(assigns) do
    for user <- assigns[:users] do
      # Bad! No key provided
      %{
        id: user.id,
        name: user.name,
        [...]
      }
    end
  end
  ```

  Because LiveData has no way of knowing which parts of your data structure
  it can use as a comparison key when diffing, this would produce inefficient
  diffs.

  The data for users can be uniquely identified by `user.id`. We can inform
  LiveData of that fact by doing the following:

  ```elixir
  deft render(assigns) do
    for user <- assigns[:users] do
      # Good! Key provided with `keyed` macro
      keyed user.id, %{
        id: user.id,
        name: user.name,
        [...]
      }
    end
  end
  ```

  This will make LiveData produce efficient diffs whether the users in
  the list change order, any individual properties change, or other changes.
  """

  alias LiveData.AsyncResult
  alias LiveData.{Socket, Async}

  @type rendered :: any()

  @callback mount(params :: any(), Socket.t()) :: {:ok, Socket.t()}

  @callback handle_event(event :: String.t(), payload :: map(), Socket.t()) :: {:ok, Socket.t()}
  @callback handle_info(message :: any(), Socket.t()) :: {:ok, Socket.t()}

  @callback render(Socket.assigns()) :: rendered()

  @optional_callbacks mount: 2, handle_event: 3, handle_info: 2

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      import LiveData
      @behaviour LiveData
    end
  end

  def assign(%Socket{} = socket, keyword_or_map)
      when is_map(keyword_or_map) or is_list(keyword_or_map) do
    Enum.reduce(keyword_or_map, socket, fn {key, value}, acc ->
      assign(acc, key, value)
    end)
  end

  def assign(%Socket{} = socket, key, value) do
    validate_assign_key!(key)
    LiveData.Utils.assign(socket, key, value)
  end

  def assign_new(%Socket{} = socket, key, fun) when is_function(fun, 1) do
    validate_assign_key!(key)
    LiveData.Utils.assign_new(socket, key, fun)
  end

  def assign_new(%{} = assigns, key, fun) when is_function(fun, 1) do
    validate_assign_key!(key)

    case assigns do
      %{^key => _} -> assigns
      _ -> Map.put_new(assigns, key, fun.(assigns))
    end
  end

  @doc """
  Assigns keys asynchronously.

  The task is linked to the caller and errors are wrapped.
  Each key passed to `assign_async/3` will be assigned to
  an `%AsyncResult{}` struct holding the status of the operation
  and the result when completed.

  ## Examples

      def mount(%{"slug" => slug}, _, socket) do
        {:ok,
         socket
         |> assign(:foo, "bar")
         |> assign_async(:org, fn -> {:ok, %{org: fetch_org!(slug)}} end)
         |> assign_async([:profile, :rank], fn -> {:ok, %{profile: ..., rank: ...}} end)}
      end

  See the moduledoc for more information.
  """
  def assign_async(%Socket{} = socket, key_or_keys, func)
      when (is_atom(key_or_keys) or is_list(key_or_keys)) and
             is_function(func, 0) do
    Async.assign_async(socket, key_or_keys, func)
  end

  def async_result(%AsyncResult{} = async_assign, clauses) do
    if !Keyword.keyword?(clauses) or
         !Enum.all?(clauses, fn {key, _} -> key in [:ok, :loading, :failed] end) do
      raise ArgumentError,
            "invalid clauses, expected :ok, :loading, or :failed: #{inspect(clauses)}"
    end

    cond do
      async_assign.ok? ->
        clauses[:ok].(async_assign.result)

      async_assign.loading ->
        clauses[:loading].()

      !is_nil(async_assign.failed) ->
        clauses[:failed].(async_assign.result)
    end
  end

  @doc """
  Adds a flash message to the socket to be displayed.

  *Note*: While you can use `put_flash/3` inside a `Phoenix.LiveComponent`,
  components have their own `@flash` assigns. The `@flash` assign
  in a component is only copied to its parent LiveView if the component
  calls `push_navigate/2` or `push_patch/2`.

  *Note*: You must also place the `LiveData.Router.fetch_live_flash/2`
  plug in your browser's pipeline in place of `fetch_flash` for LiveView flash
  messages be supported, for example:

      import LiveData.Router

      pipeline :browser do
        ...
        plug :fetch_live_flash
      end

  ## Examples

      iex> put_flash(socket, :info, "It worked!")
      iex> put_flash(socket, :error, "You can't access that page")
  """

  defdelegate put_flash(socket, kind, msg), to: LiveData.Utils

  @doc """
  Clears the flash.

  ## Examples

      iex> clear_flash(socket)
  """
  defdelegate clear_flash(socket), to: LiveData.Utils

  @doc """
  Clears a key from the flash.

  ## Examples

      iex> clear_flash(socket, :info)
  """
  defdelegate clear_flash(socket, key), to: LiveData.Utils

  @doc """
  Pushes an event to the client.

  Events can be handled in two ways:

    1. They can be handled on `window` via `addEventListener`.
       A "phx:" prefix will be added to the event name.

    2. They can be handled inside a hook via `handleEvent`.

  Note that events are dispatched to all active hooks on the client who are
  handling the given `event`. If you need to scope events, then this must
  be done by name spacing them.

  ## Hook example

  If you push a "scores" event from your LiveView:

      {:noreply, push_event(socket, "scores", %{points: 100, user: "josé"})}

  A hook declared via `phx-hook` can handle it via `handleEvent`:

      this.handleEvent("scores", data => ...)

  ## `window` example

  All events are also dispatched on the `window`. This means you can handle
  them by adding listeners. For example, if you want to remove an element
  from the page, you can do this:

      {:noreply, push_event(socket, "remove-el", %{id: "foo-bar"})}

  And now in your app.js you can register and handle it:

      window.addEventListener(
        "phx:remove-el",
        e => document.getElementById(e.detail.id).remove()
      )

  """
  defdelegate push_event(socket, event, payload), to: LiveData.Utils

  defp validate_assign_key!(key) when is_atom(key), do: :ok

  defp validate_assign_key!(key) do
    raise ArgumentError, "assigns in LiveData must be atoms, got: #{inspect(key)}"
  end

  def redirect(socket, opts)

  def redirect(%Socket{} = socket, to: url) do
    validate_local_url!(url, "redirect/2")
    put_redirect(socket, {:redirect, %{to: url}})
  end

  def redirect(%Socket{} = socket, external: url) do
    case url do
      {scheme, rest} ->
        put_redirect(socket, {:redirect, %{external: "#{scheme}:#{rest}"}})

      url when is_binary(url) ->
        external_url = LiveData.Utils.valid_string_destination!(url, "redirect/2")
        put_redirect(socket, {:redirect, %{external: external_url}})

      other ->
        raise ArgumentError,
              "expected :external option in redirect/2 to be valid URL, got: #{inspect(other)}"
    end
  end

  def redirect(%Socket{}, _) do
    raise ArgumentError, "expected :to or :external option in redirect/2"
  end

  @invalid_local_url_chars ["\\"]

  defp validate_local_url!("//" <> _ = to, where) do
    raise_invalid_local_url!(to, where)
  end

  defp validate_local_url!("/" <> _ = to, where) do
    if String.contains?(to, @invalid_local_url_chars) do
      raise ArgumentError, "unsafe characters detected for #{where} in URL #{inspect(to)}"
    else
      to
    end
  end

  defp validate_local_url!(to, where) do
    raise_invalid_local_url!(to, where)
  end

  defp raise_invalid_local_url!(to, where) do
    raise ArgumentError, "the :to option in #{where} expects a path but was #{inspect(to)}"
  end

  defp put_redirect(%Socket{redirected: nil} = socket, command) do
    %Socket{socket | redirected: command}
  end

  defp put_redirect(%Socket{redirected: to} = _socket, _command) do
    raise ArgumentError, "socket already prepared to redirect with #{inspect(to)}"
  end

  def debug_prints?, do: Application.get_env(:live_data, :deft_compiler_debug_prints, false)
end
