defmodule LiveData.Router do
  @moduledoc """
  Router for Phoenix LiveDatas.
  """

  defmacro __using__(opts) do
    quote do
      import LiveData.Router

      Module.register_attribute(__MODULE__, :phoenix_channels, accumulate: true)
      Module.register_attribute(__MODULE__, :phoenix_data_view_routes, accumulate: true)

      # === Begin Socket
      @behaviour Phoenix.Socket
      @before_compile LiveData.Router
      @phoenix_socket_options unquote(opts)

      @behaviour Phoenix.Socket.Transport

      @doc false
      def child_spec(opts) do
        Phoenix.Socket.__child_spec__(__MODULE__, opts, @phoenix_socket_options)
      end

      @doc false
      def connect(map), do: Phoenix.Socket.__connect__(__MODULE__, map, @phoenix_socket_options)

      @doc false
      def init(state), do: Phoenix.Socket.__init__(state)

      @doc false
      def handle_in(message, state), do: Phoenix.Socket.__in__(message, state)

      @doc false
      def handle_info(message, state), do: Phoenix.Socket.__info__(message, state)

      @doc false
      def terminate(reason, state), do: Phoenix.Socket.__terminate__(reason, state)
      # === End Socket

      @impl Phoenix.Socket
      def connect(params, %Phoenix.Socket{} = socket, connect_info) do
        {:ok, socket}
      end

      @impl Phoenix.Socket
      def id(_socket), do: nil

      defoverridable Phoenix.Socket
    end
  end

  @doc """
  Add a regular phoenix channel to the socket. See `Phoenix.Socket.channel/3`.

  The `dv:*` channels are reserved by the implementation.
  """
  defmacro channel(topic_pattern, module, opts \\ []) do
    # Tear the alias to simply store the root in the AST.
    # This will make Elixir unable to track the dependency between
    # endpoint <-> socket and avoid recompiling the endpoint
    # (alongside the whole project) whenever the socket changes.
    module = tear_alias(module)

    case topic_pattern do
      "dv:" <> _rest ->
        raise ArgumentError, "the `dv:*` topic namespace is reserved"

      _ ->
        nil
    end

    quote do
      @phoenix_channels {unquote(topic_pattern), unquote(module), unquote(opts)}
    end
  end

  # TODO add route parameter validation support
  @doc """
  Adds a route to a LiveData.
  """
  defmacro data(route, module, opts \\ []) do
    module = tear_alias(module)

    quote do
      @phoenix_data_view_routes {
        unquote(route),
        unquote(module),
        unquote(opts),
        LiveData.Router.__live__(__MODULE__)
      }
    end
  end

  @doc false
  def __live__(router) do
    Module.get_attribute(router, :phoenix_live_session_current) ||
      %{name: :default, extra: %{}, vsn: session_vsn(router)}
  end

  defp tear_alias({:__aliases__, meta, [h | t]}) do
    alias = {:__aliases__, meta, [h]}

    quote do
      Module.concat([unquote(alias) | unquote(t)])
    end
  end

  defp tear_alias(other), do: other

  defmacro __before_compile__(env) do
    channels = Module.get_attribute(env.module, :phoenix_channels)
    data_views = Module.get_attribute(env.module, :phoenix_data_view_routes)

    channel_defs =
      for {topic_pattern, module, opts} <- channels do
        topic_pattern
        |> to_topic_match()
        |> def_channel(module, opts)
      end

    data_view_defs =
      for {route, module, opts, live_session} <- data_views do
        def_data_view(route, module, opts, live_session)
      end

    quote do
      # All channels under "dv:*" are reserved.
      def __channel__("dv:c:" <> _rest),
        do:
          {LiveData.Channel,
           [assigns: %{live_data_handler: {unquote(env.module), :__live_data_handler__}}]}

      def __channel__("dv:" <> _rest), do: nil
      unquote(channel_defs)
      def __channel__(_topic), do: nil

      unquote(data_view_defs)
      def __live_data__(_route), do: nil

      require Logger

      def __live_data_handler__(%{"r" => route} = x) do
        Logger.debug("SDUI Render: #{route}")
        __live_data__(route)
      end
    end
  end

  defp to_topic_match(topic_pattern) do
    case String.split(topic_pattern, "*") do
      [prefix, ""] -> quote do: <<unquote(prefix) <> _rest>>
      [bare_topic] -> bare_topic
      _ -> raise ArgumentError, "channels using splat patterns must end with *"
    end
  end

  defp def_channel(topic_match, channel_module, opts) do
    quote do
      def __channel__(unquote(topic_match)), do: unquote({channel_module, Macro.escape(opts)})
    end
  end

  defp def_data_view(route, data_view_module, opts, live_session) do
    quote do
      def __live_data__(unquote(route)),
        do:
          {unquote(data_view_module), unquote(Macro.escape(opts)),
           unquote(Macro.escape(live_session))}
    end
  end

  defmacro live_session(name, opts \\ [], do: block) do
    opts =
      if Macro.quoted_literal?(opts) do
        Macro.prewalk(opts, &expand_alias(&1, __CALLER__))
      else
        opts
      end

    quote do
      unquote(__MODULE__).__live_session__(__MODULE__, unquote(opts), unquote(name))
      unquote(block)
      Module.delete_attribute(__MODULE__, :phoenix_live_session_current)
    end
  end

  defp expand_alias({:__aliases__, _, _} = alias, env),
    do: Macro.expand(alias, %{env | function: {:mount, 3}})

  defp expand_alias(other, _env), do: other

  @doc false
  def __live_session__(module, opts, name) do
    Module.register_attribute(module, :phoenix_live_sessions, accumulate: true)
    vsn = session_vsn(module)

    unless is_atom(name) do
      raise ArgumentError, """
      expected live_session name to be an atom, got: #{inspect(name)}
      """
    end

    extra = validate_live_session_opts(opts, module, name)

    if nested = Module.get_attribute(module, :phoenix_live_session_current) do
      raise """
      attempting to define live_session #{inspect(name)} inside #{inspect(nested.name)}.
      live_session definitions cannot be nested.
      """
    end

    if name in Module.get_attribute(module, :phoenix_live_sessions) do
      raise """
      attempting to redefine live_session #{inspect(name)}.
      live_session routes must be declared in a single named block.
      """
    end

    current = %{name: name, extra: extra, vsn: vsn}
    Module.put_attribute(module, :phoenix_live_session_current, current)
    Module.put_attribute(module, :phoenix_live_sessions, name)
  end

  @live_session_opts [:on_mount, :session]
  defp validate_live_session_opts(opts, module, _name) when is_list(opts) do
    Enum.reduce(opts, %{}, fn
      {:session, val}, acc when is_map(val) or (is_tuple(val) and tuple_size(val) == 3) ->
        Map.put(acc, :session, val)

      {:session, bad_session}, _acc ->
        raise ArgumentError, """
        invalid live_session :session

        expected a map with string keys or an MFA tuple, got #{inspect(bad_session)}
        """

      {:on_mount, on_mount}, acc ->
        hooks = Enum.map(List.wrap(on_mount), &LiveData.Lifecycle.on_mount(module, &1))
        Map.put(acc, :on_mount, hooks)

      {key, _val}, _acc ->
        raise ArgumentError, """
        unknown live_session option "#{inspect(key)}"

        Supported options include: #{inspect(@live_session_opts)}
        """
    end)
  end

  defp validate_live_session_opts(invalid, _module, name) do
    raise ArgumentError, """
    expected second argument to live_session to be a list of options, got:

        live_session #{inspect(name)}, #{inspect(invalid)}
    """
  end

  defp session_vsn(module) do
    if vsn = Module.get_attribute(module, :phoenix_session_vsn) do
      vsn
    else
      vsn = System.system_time()
      Module.put_attribute(module, :phoenix_session_vsn, vsn)
      vsn
    end
  end
end
