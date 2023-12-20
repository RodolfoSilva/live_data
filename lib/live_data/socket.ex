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
            assigns: %{}

  @type assigns :: map()
end
