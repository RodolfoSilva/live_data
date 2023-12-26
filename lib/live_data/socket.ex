defmodule LiveData.Socket do
  @moduledoc false

  defstruct endpoint: nil,
            transport_pid: nil,
            redirected: nil,
            router: nil,
            private: %{
              live_temp: %{},
              lifecycle: nil
            },
            assigns: %{
              __changed__: %{}
            }

  @type assigns :: map()

  def new_assign(attrs) do
    %{assigns: assigns} = %__MODULE__{}

    Map.merge(assigns, attrs)
  end
end
