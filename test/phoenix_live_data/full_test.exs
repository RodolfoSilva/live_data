defmodule LiveData.FullTest do
  use ExUnit.Case, async: true

  import LiveData.Test

  for i <- 1..500 do
    test "testing  round #{i}" do
      {:ok, view, data} = live_data(LiveData.Test.TestingData)
      assert data == %{"counter" => 0, "lazy_counter" => "Loading..."}
      assert act_and_render(view) == %{"counter" => 0, "lazy_counter" => 3}
      assert render_server_event(view, :increment) == %{"counter" => 1, "lazy_counter" => 3}
      assert render_client_event(view, "increment") == %{"counter" => 2, "lazy_counter" => 3}
    end
  end
end
