defmodule LiveData.FullTest do
  use ExUnit.Case, async: true

  import LiveData.Test

  for i <- 1..500 do
    test "testing  round #{i}" do
      {:ok, view, data} = live_data(LiveData.Test.TestingData)
      assert data == %{"counter" => 0, "lazy_counter" => "Loading..."}
      assert [] = get_events(view)
      assert is_nil(get_flash(view))
      assert act_and_render(view) == %{"counter" => 0, "lazy_counter" => 3}
      assert render_server_event(view, :increment) == %{"counter" => 1, "lazy_counter" => 3}
      assert [{"chart", %{}}] = get_events(view)
      assert get_flash(view) == %{"info" => "Incremented!"}
      assert render_client_event(view, "increment") == %{"counter" => 2, "lazy_counter" => 3}
      assert [] = get_events(view)
      assert is_nil(get_flash(view))
    end
  end
end
