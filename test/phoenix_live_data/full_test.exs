defmodule LiveData.FullTest do
  use ExUnit.Case

  import LiveData.Test

  test "testing" do
    {:ok, view, data} = live_data(LiveData.Test.TestingData)
    assert data == %{"counter" => 0}
    assert render_server_event(view, :increment) == %{"counter" => 1}
    assert render_client_event(view, "increment") == %{"counter" => 2}
  end
end
