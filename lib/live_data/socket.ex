defmodule LiveData.Socket do
  @moduledoc false

  defstruct endpoint: nil,
            transport_pid: nil,
            redirected: nil,
            router: nil,
            private: %{},
            assigns: %{}

  @type assigns :: map()
end
